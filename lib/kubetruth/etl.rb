require_relative 'logging'
require_relative 'ctapi'
require_relative 'kubeapi'
require 'active_support/core_ext/hash/keys'

module Kubetruth
  class ETL
    include GemLogger::LoggerSupport

    def initialize(key_prefixes:, key_patterns:,
                   namespace_template:, name_template:, key_template:,
                   ct_context:, kube_context:)

      @key_prefixes = key_prefixes
      @key_patterns = key_patterns
      @name_template = name_template
      @namespace_template = namespace_template
      @key_template = key_template
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
      @kubeapis[namespace] ||= KubeApi.new(**@kube_context.merge(namespace: namespace))
    end

    def apply(dry_run: false, skip_secrets: false, secrets_as_config: false)
      param_groups = get_param_groups
      logger.debug { "Parameter groupings: #{param_groups.keys}" }

      if secrets_as_config && ! skip_secrets
        config_param_groups = param_groups
        secret_param_groups = {}
      else
        config_param_groups, secret_param_groups = partition_secrets(param_groups)
      end

      if dry_run
        logger.info("Performing dry-run")

        logger.info("Config maps that would be created are:")
        logger.info(config_param_groups.pretty_print_inspect)

        if ! secrets_as_config && ! skip_secrets
          logger.info("Secrets that would be created are:")
          logger.info(secret_param_groups.pretty_print_inspect)
        end
        return
      else
        apply_config_maps(config_param_groups)

        if ! secrets_as_config && ! skip_secrets
          apply_secrets(secret_param_groups)
        end
      end
    end

    def partition_secrets(param_groups)
      config_param_groups = {}
      secret_param_groups = {}
      param_groups.each do |k, v|
        parts = v.group_by(&:secret)
        config_param_groups[k] = parts[false] if parts[false].present?
        secret_param_groups[k] = parts[true] if parts[true].present?
      end
      return config_param_groups, secret_param_groups
    end

    def get_param_groups
      # First search for all the selected parameters
      #
      filtered_params = []
      @key_prefixes.each do |key_prefix|
        params = ctapi.parameters(searchTerm: key_prefix)
        # ct api currently only has a search, not a prefix filter
        params = params.select { |param| param.key =~ /^#{key_prefix}/ }
        filtered_params = (filtered_params + params).uniq {|param| param.key }
      end
      logger.debug { "Filtered params: #{filtered_params.inspect}"}

      # Group those parameters by the name selected by the name_pattern
      #
      param_groups = {}
      @key_patterns.each do |key_pattern|
        logger.debug {"Looking for key pattern matches to '#{key_pattern}'"}

        filtered_params.each do |param|
          if matches = param.key.match(key_pattern)
            matches_hash = matches.named_captures.symbolize_keys
            matches_hash = Hash[*matches_hash.collect {|k, v| [k, v, "#{k}_upcase".to_sym, v.upcase]}.flatten]

            logger.debug {"Pattern matches '#{param.key}' with: #{matches_hash}"}

            namespace = dns_friendly(@namespace_template % matches_hash) if @namespace_template
            name = dns_friendly(@name_template % matches_hash)
            key = @key_template % matches_hash
            param.original_key, param.key = param.key, key

            group_key = {namespace: namespace, name: name}
            param_groups[group_key] ||= []
            param_groups[group_key] << param
          else
            logger.debug {"Pattern does not match '#{param.key}'"}
          end
        end

      end

      # Returns a hash of the group name to a param hash (param_key -> param_value)
      param_groups
    end

    def dns_friendly(str)
      dns_friendly = str.to_s.gsub(/[^-.a-zA-Z0-9)]+/, '-')
      dns_friendly = dns_friendly.gsub(/(^[^a-zA-Z0-9]+)|([^a-zA-Z0-9]+$)/, '')
      dns_friendly
    end

    def apply_config_maps(param_groups)
      logger.info("Applying config maps")

      # For each set of parameters grouped by name, add those parameters
      # to the config map with that name
      #

      param_groups.collect {|k, v| k[:namespace] }.sort.uniq.each do |ns|
        kapi = kubeapi(ns)
        # only create namespace when user chooses to use multiple namespaces determined from the pattern
        kapi.ensure_namespace if @namespace_template
        logger.debug { "Existing config maps (ns=#{ns}): #{kapi.get_config_map_names}" }
      end

      param_groups.each do |k, v|
        config_map_namespace = k[:namespace]
        config_map_name = k[:name]
        kapi = kubeapi(config_map_namespace)
        param_hash = Hash[v.collect {|param| [param.key, param.value]}]

        begin
          logger.debug { "Namespace '#{kapi.namespace}'" }
          resource = kapi.get_config_map(config_map_name)
          data = resource.data.to_h
          logger.debug("Config map for '#{config_map_name}': #{data.inspect}")
          if ! kapi.under_management?(resource)
            logger.info "Skipping config map '#{config_map_name}' as it doesn't have the kubetruth label"
          elsif param_hash != data.transform_keys! {|k| k.to_s }
            logger.info "Updating config map '#{config_map_name}' with params: #{param_hash.inspect}"
            kapi.update_config_map(config_map_name, param_hash)
          else
            logger.info "No changes needed for config map '#{config_map_name}' with params: #{param_hash.inspect}}"
          end
        rescue Kubeclient::ResourceNotFoundError
          logger.info "Creating config map '#{config_map_name}' with params: #{param_hash.inspect}}"
          kapi.create_config_map(config_map_name, param_hash)
        end
      end
    end

    def apply_secrets(param_groups)
      logger.info("Applying secrets")

      # For each set of parameters grouped by name, add those parameters
      # to the secret with that name
      #

      param_groups.collect {|k, v| k[:namespace] }.uniq.each do |ns|
        kapi = kubeapi(ns)
        # only create namespace when user chooses to use multiple namespaces determined from the pattern
        kapi.ensure_namespace if @namespace_template
        logger.debug { "Existing secrets (ns=#{kapi.namespace}): #{kapi.get_secret_names}" }
      end

      param_groups.each do |k, v|

        secret_namespace = k[:namespace]
        secret_name = k[:name]
        kapi = kubeapi(secret_namespace)

        param_hash = Hash[v.collect {|param| [param.key, param.value]}]

        begin
          logger.debug { "Namespace '#{kapi.namespace}'" }
          resource = kapi.get_secret(secret_name)
          data = kapi.secret_hash(resource)
          logger.debug { "Secret keys for '#{secret_name}': #{data.transform_keys! {|k| k.to_s }}" }
          if ! kapi.under_management?(resource)
            logger.info "Skipping secret '#{secret_name}' as it doesn't have a label indicating it is under kubetruth management"
          elsif param_hash != data.transform_keys! {|k| k.to_s }
            logger.info "Updating secret '#{secret_name}' with params: #{param_hash.keys.inspect}"
            kapi.update_secret(secret_name, param_hash)
          else
            logger.info "No changes needed for secret '#{secret_name}' with params: #{param_hash.keys.inspect}}"
          end
        rescue Kubeclient::ResourceNotFoundError
          logger.info "Creating secret '#{secret_name}' with params: #{param_hash.keys.inspect}}"
          kapi.create_secret(secret_name, param_hash)
        end
      end
    end

  end
end
