require_relative 'logging'
require_relative 'ctapi'
require_relative 'kubeapi'
require 'active_support/core_ext/hash/keys'

module Kubetruth
  class ETL
    include GemLogger::LoggerSupport

    def initialize(key_prefixes:, key_patterns:,
                   name_template:, key_template:,
                   ct_context:, kube_context:)

      @key_prefixes = key_prefixes
      @key_patterns = key_patterns
      @name_template = name_template
      @key_template = key_template
      @ct_context = ct_context
      @kube_context = kube_context
    end

    def ctapi
      @ctapi ||= begin
        ctx = @ct_context.dup
        @ctapi_class = Kubetruth::CtApi(api_key: ctx.delete(:api_key), api_url: ctx.delete(:api_url))
        @ctapi_class.new(**ctx)
      end
    end

    def kubeapi
      @kubeapi ||= KubeApi.new(**@kube_context)
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

      # Group those parameters by the name selected by the key_pattern
      #
      param_groups = {}
      @key_patterns.each do |key_pattern|
        logger.debug {"Looking for key pattern matches to '#{key_pattern}'"}

        filtered_params.each do |param|
          if matches = param.key.match(key_pattern)
            matches_hash = matches.named_captures.symbolize_keys
            matches_hash = Hash[*matches_hash.collect {|k, v| [k, v, "#{k}_upcase".to_sym, v.upcase]}.flatten]

            logger.debug {"Pattern matches '#{param.key}' with: #{matches_hash}"}
            name = @name_template % matches_hash
            key = @key_template % matches_hash
            param.original_key, param.key = param.key, key
            param_groups[name] ||= []
            param_groups[name] << param
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

      logger.debug { "Existing config maps: #{kubeapi.get_config_map_names}" }

      param_groups.each do |k, v|

        config_map_name = dns_friendly(k)

        param_hash = Hash[v.collect {|param| [param.key, param.value]}]

        begin
          data = kubeapi.get_config_map(config_map_name)
          logger.debug("Config map for '#{config_map_name}': #{data.inspect}")
          if param_hash != data.transform_keys! {|k| k.to_s }
            logger.info "Updating config map '#{config_map_name}' with params: #{param_hash.inspect}"
            kubeapi.update_config_map(config_map_name, param_hash)
          else
            logger.info "No changes needed for config map '#{config_map_name}' with params: #{param_hash.inspect}}"
          end
        rescue Kubeclient::ResourceNotFoundError
          logger.info "Creating config map '#{config_map_name}' with params: #{param_hash.inspect}}"
          kubeapi.create_config_map(config_map_name, param_hash)
        end
      end
    end

    def apply_secrets(param_groups)
      logger.info("Applying secrets")

      # For each set of parameters grouped by name, add those parameters
      # to the secret with that name
      #
      logger.debug { "Existing secrets: #{kubeapi.get_secret_names}" }

      param_groups.each do |k, v|

        secret_name = dns_friendly(k)

        param_hash = Hash[v.collect {|param| [param.key, param.value]}]

        begin
          data = kubeapi.get_secret(secret_name)
          logger.debug("Secret for '#{secret_name}': #{data}")
          if param_hash != data.transform_keys! {|k| k.to_s }
            logger.info "Updating secret '#{secret_name}' with params: #{param_hash.keys.inspect}"
            kubeapi.update_secret(secret_name, param_hash)
          else
            logger.info "No changes needed for secret '#{secret_name}' with params: #{param_hash.keys.inspect}}"
          end
        rescue Kubeclient::ResourceNotFoundError
          logger.info "Creating secret '#{secret_name}' with params: #{param_hash.keys.inspect}}"
          kubeapi.create_secret(secret_name, param_hash)
        end
      end
    end

  end
end
