require 'benchmark'
require 'yaml'
require 'yaml/safe_load_stream'
using YAMLSafeLoadStream

require_relative 'config'
require_relative 'ctapi'
require_relative 'kubeapi'
require_relative 'project_collection'

module Kubetruth
  class ETL
    include GemLogger::LoggerSupport

    def initialize(kube_context:, dry_run: false)
      @kube_context = kube_context
      @dry_run = dry_run
    end

    def kubeapi
      @kubeapi ||= KubeApi.new(**@kube_context)
    end

    def interruptible_sleep(interval)
      @sleeper = Thread.current
      Kernel.sleep interval
    end

    def interrupt_sleep
      Thread.new { @sleeper&.run }
    end

    def with_polling(interval, &block)
      while true

        begin
          watcher = kubeapi.watch_project_mappings

          begin
            thr = Thread.new do
              logger.debug "Created watcher for CRD"
              watcher.each do |notice|
                logger.debug {"Interrupting polling sleep, CRD watcher woke up for: #{notice}"}
                interrupt_sleep
                break
              end
              logger.debug "CRD watcher exiting"
            end

            run_time = Benchmark.measure do
              begin
                block.call
              rescue Kubetruth::Template::Error => e
                logger.error e.message
              rescue => e
                logger.log_exception(e, "Failure while applying config transforms")
              end
            end
            logger.info "Benchmark: #{run_time}"

            logger.info("Poller sleeping for #{interval}")
            interruptible_sleep(interval)
          ensure
            watcher.finish
            thr.join(5)
          end

        rescue => e
          logger.log_exception(e, "Failure in watch/polling logic")
        end

      end
    end

    def load_config
      configs = []
      mappings_by_ns = kubeapi.get_project_mappings
      primary_mappings = mappings_by_ns.delete(kubeapi.namespace)
      raise Error.new("A default set of mappings is required in the namespace kubetruth is installed in (#{kubeapi.namespace})") unless primary_mappings

      primary_config = Kubetruth::Config.new(primary_mappings.values)
      logger.info {"Processing primary mappings for namespace '#{kubeapi.namespace}'"}
      configs << primary_config
      yield kubeapi.namespace, primary_config if block_given?

      mappings_by_ns.each do |namespace, ns_mappings|
        secondary_mappings = primary_mappings.deep_merge(ns_mappings)
        secondary_config = Kubetruth::Config.new(secondary_mappings.values)
        logger.info {"Processing secondary mappings for namespace '#{namespace}'"}
        configs << secondary_config
        yield namespace, secondary_config if block_given?
      end

      configs
    end

    def apply
      logger.warn("Performing dry-run") if @dry_run

      load_config do |namespace, config|
        project_collection = ProjectCollection.new

        # Load all projects that are used
        all_specs = [config.root_spec] + config.override_specs
        project_selectors = all_specs.collect(&:project_selector)
        included_projects = all_specs.collect(&:included_projects).flatten.uniq

        project_collection.names.each do |project_name|
          active = included_projects.any? {|p| p == project_name }
          active ||= project_selectors.any? {|s| s =~ project_name }
          if active
            project_spec = config.spec_for_project(project_name)
            project_collection.create_project(name: project_name, spec: project_spec)
          end
        end

        project_collection.projects.values.each do |project|

          match = project.name.match(project.spec.project_selector)
          if match.nil?
            logger.info "Skipping project '#{project.name}' as it does not match any selectors"
            next
          end

          if project.spec.skip
            logger.info "Skipping project '#{project.name}'"
            next
          end

          # constructing the hash will cause any overrides to happen in the right
          # order (includer wins over last included over first included)
          params = project.all_parameters
          parts = params.group_by(&:secret)
          config_params, secret_params = (parts[false] || []), (parts[true] || [])
          config_param_hash = params_to_hash(config_params)
          secret_param_hash = params_to_hash(secret_params)

          parameter_origins = project.parameter_origins
          param_origins_parts = parameter_origins.group_by {|k, v| config_param_hash.has_key?(k) }
          config_origins = Hash[param_origins_parts[true] || []]
          secret_origins = Hash[param_origins_parts[false] || []]

          project.spec.resource_templates.each_with_index do |pair, i|
            template_name, template = *pair
            logger.debug { "Processing template '#{template_name}' (#{i+1}/#{project.spec.resource_templates.size})" }
            resource_yml = template.render(
              template: template_name,
              kubetruth_namespace: kubeapi.namespace,
              mapping_namespace: namespace,
              project: project.name,
              project_heirarchy: project.heirarchy,
              debug: logger.debug?,
              parameters: config_param_hash,
              parameter_origins: config_origins,
              secrets: secret_param_hash,
              secret_origins: secret_origins,
              context: project.spec.context
            )

            template_id = "mapping: #{project.spec.name}, mapping_namespace: #{namespace}, project: #{project.name}, template: #{template_name}"
            parsed_ymls = YAML.safe_load_stream(resource_yml, template_id)
            logger.debug {"Skipping empty template"} if parsed_ymls.empty?
            parsed_ymls.each do |parsed_yml|
              kube_apply(parsed_yml)
            end

          end
        end
      end

    end

    def params_to_hash(param_list)
      Hash[param_list.collect {|param| [param.key, param.value]}]
    end

    def kube_apply(parsed_yml)
      kind = parsed_yml["kind"]
      name = parsed_yml["metadata"]["name"]
      namespace = parsed_yml["metadata"]["namespace"]
      if namespace.blank?
        namespace = parsed_yml["metadata"]["namespace"] = kubeapi.namespace
      end

      kubeapi.set_managed(parsed_yml)

      ident = "'#{namespace}:#{kind}:#{name}'"
      logger.info("Applying kubernetes resource #{ident}")

      kubeapi.ensure_namespace(namespace) unless @dry_run

      begin
        resource = kubeapi.get_resource(kind.downcase.pluralize, name, namespace)
        if ! kubeapi.under_management?(resource)
          logger.warn "Skipping #{ident} as it doesn't have a label indicating it is under kubetruth management"
        else
          # apply is server side, and doesn't update unless there are diffs (the
          # metadata.resourceVersion/creationTimestamp/uid stay constant)
          # Trying to compare the fetched resource to the generated one doesn't
          # work as there a bunch of fields we don't control, so we just rely on
          # the server-side apply to do the right thing.
          logger.info "Updating kubernetes resource #{ident}"
          kubeapi.apply_resource(parsed_yml) unless @dry_run
        end
      rescue Kubeclient::ResourceNotFoundError
        logger.info "Creating kubernetes resource #{ident}"
        kubeapi.apply_resource(parsed_yml) unless @dry_run
      end
    end

  end
end
