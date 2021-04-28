require_relative 'logging'
require_relative 'config'
require_relative 'ctapi'
require_relative 'kubeapi'
require 'active_support/core_ext/hash/keys'

module Kubetruth
  class ETL
    include GemLogger::LoggerSupport

    # From kubernetes error message
    DNS_VALIDATION_RE = /^[a-z0-9]([-a-z0-9]*[a-z0-9])?(\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*$/

    def initialize(ct_context:, kube_context:)
      @ct_context = ct_context
      @kube_context = kube_context
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

    def load_config
      mappings = kubeapi(@kube_context[:namespace]).get_project_mappings
      Kubetruth::Config.new(mappings)
    end

    def apply(dry_run: false)
      config = load_config

      projects = ctapi.project_names

      projects.each do |project|

        match = project.match(config.root_spec.project_selector)
        if match.nil?
          logger.info "Project '#{project}' does not match root selector #{config.root_spec.project_selector}"
          next
        else
          logger.info "Project '#{project}' matches root selector #{config.root_spec.project_selector}"
        end
        matches_hash = match.named_captures.symbolize_keys

        project_spec = config.spec_for_project(project)
        if project_spec.skip
          logger.info "Skipping project '#{project}'"
          next
        end

        # Add in matches from project specific selector, the match will always
        # succeed as the spec is either the root spec, or its project_selector
        # has already matched
        match = project.match(project_spec.project_selector)
        matches_hash = matches_hash.merge(match.named_captures.symbolize_keys)
        matches_hash[:project] = project unless matches_hash.has_key?(:project)
        matches_hash = Hash[*matches_hash.collect {|k, v| [k, v, "#{k}_upcase".to_sym, v.upcase]}.flatten]

        namespace = dns_friendly(project_spec.namespace_template % matches_hash)
        configmap_name = dns_friendly(project_spec.configmap_name_template % matches_hash)
        secret_name = dns_friendly(project_spec.secret_name_template % matches_hash)

        params = get_params(project, project_spec, template_matches: matches_hash)
        logger.debug { "Parameters selected for #{project}: #{params.collect {|p| "#{p.original_key} => #{p.key}"}.inspect}" }

        parts = params.group_by(&:secret)
        config_params, secret_params = (parts[false] || []), (parts[true] || [])

        if dry_run
          logger.info("Performing dry-run")

          logger.info("Config maps that would be created are:")
          logger.info(config_params.pretty_print_inspect)

          if ! project_spec.skip_secrets
            logger.info("Secrets that would be created are:")
            secret_params.each {|p| p.value = "<masked>" if p.secret}
            logger.info(secret_params.pretty_print_inspect)
          end

          next
        else
          apply_config_map(namespace: namespace, name: configmap_name, params: config_params)

          if ! project_spec.skip_secrets
            apply_secret(namespace: namespace, name: secret_name, params: secret_params)
          end
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

      logger.debug {"Looking for key pattern matches to '#{project_spec.key_selector}'"}

      params.each do |param|
        if matches = param.key.match(project_spec.key_selector)
          matches_hash = matches.named_captures.symbolize_keys
          matches_hash[:key] = param.key unless matches_hash.has_key?(:key)
          matches_hash = Hash[*matches_hash.collect {|k, v| [k, v, "#{k}_upcase".to_sym, v.upcase]}.flatten]
          matches_hash = template_matches.merge(matches_hash)

          logger.debug {"Pattern matches '#{param.key}' with: #{matches_hash}"}

          key = project_spec.key_template % matches_hash
          param.original_key, param.key = param.key, key

          result << param
        else
          logger.debug {"Pattern does not match '#{param.key}'"}
        end
      end

      result
    end

    def dns_friendly(str)
      return str if str =~ DNS_VALIDATION_RE
      dns_friendly = str.to_s.downcase.gsub(/[^-.a-z0-9)]+/, '-')
      dns_friendly = dns_friendly.gsub(/(^[^a-z0-9]+)|([^a-z0-9]+$)/, '')
      dns_friendly
    end

    def apply_config_map(namespace:, name:, params:)
      logger.info("Applying config map #{namespace}:#{name}")

      kapi = kubeapi(namespace)
      kapi.ensure_namespace
      logger.debug { "Existing config maps (ns=#{kapi.namespace}): #{kapi.get_config_map_names}" }

      param_hash = Hash[params.collect {|param| [param.key, param.value]}]

      begin
        resource = kapi.get_config_map(name)
        data = resource.data.to_h
        logger.debug("Config map for '#{name}': #{data.inspect}")
        if ! kapi.under_management?(resource)
          logger.warn "Skipping config map '#{name}' as it doesn't have a label indicating it is under kubetruth management"
        elsif param_hash != data.transform_keys! {|k| k.to_s }
          logger.info "Updating config map '#{name}' with params: #{param_hash.inspect}"
          kapi.update_config_map(name, param_hash)
        else
          logger.info "No changes needed for config map '#{name}' with params: #{param_hash.inspect}}"
        end
      rescue Kubeclient::ResourceNotFoundError
        logger.info "Creating config map '#{name}' with params: #{param_hash.inspect}}"
        kapi.create_config_map(name, param_hash)
      end
    end

    def apply_secret(namespace:, name:, params:)
      logger.info("Applying secrets #{namespace}:#{name}")

      kapi = kubeapi(namespace)
      kapi.ensure_namespace
      logger.debug { "Existing secrets (ns=#{kapi.namespace}): #{kapi.get_secret_names}" }

      param_hash = Hash[params.collect {|param| [param.key, param.value]}]

      begin
        logger.debug { "Namespace '#{kapi.namespace}'" }
        resource = kapi.get_secret(name)
        data = kapi.secret_hash(resource)
        logger.debug { "Secret keys for '#{name}': #{data.transform_keys! {|k| k.to_s }}" }
        if ! kapi.under_management?(resource)
          logger.warn "Skipping secret '#{name}' as it doesn't have a label indicating it is under kubetruth management"
        elsif param_hash != data.transform_keys! {|k| k.to_s }
          logger.info "Updating secret '#{name}' with params: #{param_hash.keys.inspect}"
          kapi.update_secret(name, param_hash)
        else
          logger.info "No changes needed for secret '#{name}' with params: #{param_hash.keys.inspect}}"
        end
      rescue Kubeclient::ResourceNotFoundError
        logger.info "Creating secret '#{name}' with params: #{param_hash.keys.inspect}}"
        kapi.create_secret(name, param_hash)
      end
    end

  end
end
