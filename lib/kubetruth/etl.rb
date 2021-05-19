require_relative 'logging'
require_relative 'config'
require_relative 'ctapi'
require_relative 'kubeapi'
require 'active_support/core_ext/hash/keys'
require 'benchmark'

module Kubetruth
  class ETL
    include GemLogger::LoggerSupport

    def initialize(ct_context:, kube_context:, dry_run: false, metadata: true)
      @ct_context = ct_context
      @kube_context = kube_context
      @dry_run = dry_run
      @metadata = metadata
      @kubeapis = {}
    end

    def ctapi
      @ctapi ||= begin
        ctx = @ct_context.dup
        @ctapi_class = Kubetruth::CtApi(api_key: ctx.delete(:api_key), api_url: ctx.delete(:api_url))
        @ctapi_class.new(**ctx)
      end
    end

    def kubeapi(namespace)
      namespace = namespace.present? ? namespace : nil
      @kubeapis[namespace] ||= KubeApi.new(**@kube_context.merge(namespace: namespace))
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
          watcher = kubeapi(@kube_context[:namespace]).watch_project_mappings

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
      mappings = kubeapi(@kube_context[:namespace]).get_project_mappings
      Kubetruth::Config.new(mappings)
    end

    def apply
      logger.warn("Performing dry-run") if @dry_run

      config = load_config

      projects = ctapi.project_names
      project_data = {}

      projects.each do |project|

        project_spec = config.spec_for_project(project)

        match = project.match(config.root_spec.project_selector)
        if match.nil?
          logger.info "Project '#{project}' does not match root selector #{config.root_spec.project_selector.inspect}"
          next
        else
          logger.info "Project '#{project}' matches root selector #{config.root_spec.project_selector.inspect}"
        end
        matches_hash = match.named_captures.symbolize_keys

        # Add in matches from project specific selector, the match will always
        # succeed as the spec is either the root spec, or its project_selector
        # has already matched
        match = project.match(project_spec.project_selector)
        matches_hash = matches_hash.merge(match.named_captures.symbolize_keys)
        matches_hash[:project] = project unless matches_hash.has_key?(:project)

        project_data[project] ||= {}
        project_data[project][:namespace] = project_spec.namespace_template.render(**matches_hash)
        project_data[project][:configmap_name] = project_spec.configmap_name_template.render(**matches_hash)
        project_data[project][:secret_name] = project_spec.secret_name_template.render(**matches_hash)

        params = get_params(project, project_spec, template_matches: matches_hash)
        project_data[project][:params] = params
        logger.debug { "Parameters selected for #{project}: #{params.collect {|p| "#{p.original_key} => #{p.key}"}.inspect}" }
      end

      project_data.each do |project, data|

        project_spec = config.spec_for_project(project)
        if project_spec.skip
          logger.info "Skipping project '#{project}'"
          next
        end

        param_origins = {}

        # TODO: make project inclusion recursive?
        included_params = []
        project_spec.included_projects.each do |included_project|
          if included_project == project
            logger.warn("Skipping project's import of itself, included_projects for '#{project}' are: #{project_spec.included_projects.inspect}")
            next
          end
          included_data = project_data[included_project]
          if included_data.nil?
            logger.warn "Skipping the included project not selected by root selector: #{included_project}"
            next
          end

          included_data[:params].each do |p|
            param_origins[p.key] ||= []
            param_origins[p.key] << included_project
          end

          included_params.concat(included_data[:params])
        end

        data[:params].each do |p|
          param_origins[p.key] ||= []
          param_origins[p.key] << project
        end

        # constructing the hash will cause any overrides to happen in the right
        # order (includer wins over last included over first included)
        params = included_params + data[:params]
        parts = params.group_by(&:secret)
        config_params, secret_params = (parts[false] || []), (parts[true] || [])
        config_param_hash = params_to_hash(config_params)
        secret_param_hash = params_to_hash(secret_params)

        if @metadata
          metadata = {}
          metadata["project_heirarchy"] = (project_spec.included_projects + [project]).reverse.join(" -> ")

          param_origins.merge!(param_origins) do |_, v|
            origin = "#{v.pop}"
            if v.length > 0
              origin << " (#{v.reverse.join(" -> ")})"
            end
            origin
          end

          param_origins_parts = param_origins.group_by {|k, v| config_param_hash.has_key?(k) }
          config_origins = Hash[param_origins_parts[true] || []]
          secret_origins = Hash[param_origins_parts[false] || []]

          config_param_hash[:cloudtruth_metadata] = metadata.merge({ "parameter_origins" => config_origins }).to_yaml
          secret_param_hash[:cloudtruth_metadata] = metadata.merge({ "parameter_origins" => secret_origins }).to_yaml
        end

        apply_config_map(namespace: data[:namespace], name: data[:configmap_name], param_hash: config_param_hash)

        if ! project_spec.skip_secrets
          apply_secret(namespace: data[:namespace], name: data[:secret_name], param_hash: secret_param_hash)
        end
      end
    end

    def get_params(project, project_spec, template_matches: {})
      result = []

      # First search for all the selected parameters
      #
      params = ctapi.parameters(searchTerm: project_spec.key_filter, project: project)
      logger.debug do
        cleaned = params.deep_dup
        cleaned.each {|p| p.value = "<masked>" if p.secret}
        "Filtered params: #{cleaned.inspect}"
      end

      logger.debug {"Looking for key pattern matches to '#{project_spec.key_selector.inspect}'"}

      params.each do |param|
        if matches = param.key.match(project_spec.key_selector)
          matches_hash = matches.named_captures.symbolize_keys
          matches_hash[:key] = param.key unless matches_hash.has_key?(:key)
          matches_hash = template_matches.merge(matches_hash)

          logger.debug {"Pattern matches '#{param.key}' with: #{matches_hash}"}

          key = project_spec.key_template.render(**matches_hash)
          param.original_key, param.key = param.key, key

          result << param
        else
          logger.debug {"Pattern does not match '#{param.key}'"}
        end
      end

      result
    end

    def params_to_hash(param_list)
      Hash[param_list.collect {|param| [param.key, param.value]}]
    end

    def apply_config_map(namespace:, name:, param_hash:)
      logger.info("Applying config map #{namespace}:#{name}")
      logger.debug { "  with params: #{param_hash.keys.inspect}}" }

      kapi = kubeapi(namespace)
      kapi.ensure_namespace unless @dry_run
      logger.debug { "Existing config maps (ns=#{kapi.namespace}): #{kapi.get_config_map_names}" }

      begin
        resource = kapi.get_config_map(name)
        data = resource.data.to_h
        logger.debug { "Existing config map for '#{name}': #{data.inspect}" }
        if ! kapi.under_management?(resource)
          logger.warn "Skipping config map '#{name}' as it doesn't have a label indicating it is under kubetruth management"
        elsif param_hash != data.transform_keys! {|k| k.to_s }
          logger.info "Updating config map '#{name}'"
          kapi.update_config_map(name, param_hash) unless @dry_run
        else
          logger.info "No changes needed for config map '#{name}'"
        end
      rescue Kubeclient::ResourceNotFoundError
        logger.info "Creating config map '#{name}'"
        kapi.create_config_map(name, param_hash) unless @dry_run
      end
    end

    def apply_secret(namespace:, name:, param_hash:)
      logger.info("Applying secrets #{namespace}:#{name}")
      logger.debug { "  with params: #{param_hash.keys.inspect}" }

      kapi = kubeapi(namespace)
      kapi.ensure_namespace unless @dry_run
      logger.debug { "Existing secrets (ns=#{kapi.namespace}): #{kapi.get_secret_names}" }

      begin
        logger.debug { "Namespace '#{kapi.namespace}'" }
        resource = kapi.get_secret(name)
        data = kapi.secret_hash(resource)
        logger.debug { "Existing Secret for '#{name}': #{data.transform_keys! {|k| k.to_s }}" }
        if ! kapi.under_management?(resource)
          logger.warn "Skipping secret '#{name}' as it doesn't have a label indicating it is under kubetruth management"
        elsif param_hash != data.transform_keys! {|k| k.to_s }
          logger.info "Updating secret '#{name}'"
          kapi.update_secret(name, param_hash) unless @dry_run
        else
          logger.info "No changes needed for secret '#{name}'"
        end
      rescue Kubeclient::ResourceNotFoundError
        logger.info "Creating secret '#{name}'"
        kapi.create_secret(name, param_hash) unless @dry_run
      end
    end

  end
end
