require 'clamp'
require_relative 'logging'
require_relative 'ctapi'
require_relative 'kubeapi'

module Kubetruth
  class CLI < Clamp::Command

    include GemLogger::LoggerSupport

    banner <<~EOF
      Scans cloudtruth parameters for `name-pattern`, using the `name` match as
      the name of the kubernetes config_map/secrets resource to apply those
      values to
    EOF

    option ["-e", "--environment"],
           'ENV', "The environment\n",
           environment_variable: 'CT_ENV',
           required: true

    option ["-a", "--api-key"],
           'APIKEY', "The cloudtruth api key\n",
           environment_variable: 'CT_API_KEY',
           required: true

    option "--name-pattern", "PATTERN", "the pattern for generating the\nconfigmap name from key pattern matches\n",
           default: "{{name}}"

    option "--key-prefix", "PREFIX", "the key prefix to restrict the keys fetched from cloudtruth",
           default: [''],
           multivalued: true

    option "--key-pattern", "REGEX", "the key pattern for mapping cloudtruth\nparams to configmap keys.  The `name` is used for the config map naming, and the keys in that map come from the matching `key` portion.  A pattern like `^(?<key>[^\\.]+.(?<name>[^\\.]+)\\..*)` would make the key be the entire parameter key\n",
           default: ['^(?<prefix>[^\.]+)\.(?<name>[^\.]+)\.(?<key>.*)'],
           multivalued: true

    option "--[no-]skip-secrets",
           :flag, "Skip (or include secrets) in creating\nkubernetes resources\n",
           default: true

    option "--[no-]use-secret-store",
           :flag, "Secrets to secret store\n",
           default: false

    option "--kube-namespace",
           'NAMESPACE', "The kubernetes namespace\nDefaults to runtime namespace when run in kube"

    option "--kube-token",
           'TOKEN', "The kubernetes token to use for api\nDefaults to mounted when run in kube"

    option "--kube-url",
           'ENDPOINT', "The kubernetes api url\nDefaults to internal api endpoint when run in kube"

    option ["-i", "--polling-interval"], "INTERVAL", "the polling interval\n", default: 300 do |a|
      Integer(a)
    end

    option ["-d", "--debug"],
           :flag, "debug output\n",
           default: false

    option ["-q", "--quiet"],
           :flag, "suppress output\n",
           default: false

    option ["-c", "--[no-]color"],
           :flag, "colorize output (or not)\n (default: $stdout.tty?)"


    # TODO: option to map template to configmap?

    # hook into clamp lifecycle to force logging setup even when we are calling
    # a subcommand
    def parse(arguments)
      super

      level = :info
      level = :debug if debug?
      level = :error if quiet?
      Logging.setup_logging(level: level, color: color?)
    end

    def execute

      while true

        param_groups = get_param_groups
        logger.debug { "Parameter groupings: #{param_groups.keys}" }

        # TODO: handle secrets
        apply_config_maps(param_groups)

        logger.debug("Poller sleeping for #{polling_interval}")
        sleep polling_interval

      end

    end

    private

    def get_param_groups
      ctapi = CtApi.new(environment)
      # First search for all the selected parameters
      #
      filtered_params = {}
      key_prefix_list.each do |key_prefix|
        params = ctapi.parameters(searchTerm: key_prefix)
        # ct api currently only has a search, not a prefix filter
        params = params.select { |k, v| k =~ /^#{key_prefix}/ }
        filtered_params = filtered_params.merge(params)
      end
      logger.debug { "Filtered params: #{filtered_params.inspect}"}

      # Group those parameters by the name selected by the key_pattern
      #
      param_groups = {}
      key_pattern_list.each do |key_pattern|
        logger.debug {"Looking for key pattern matches to '#{key_pattern}'"}

        filtered_params.each do |k, v|
          if matches = k.match(key_pattern)
            logger.debug {"Pattern matches '#{k}' with: #{matches.inspect}"}
            name = matches[:name]
            key = matches[:key]
            param_groups[name] ||= {}
            param_groups[name][key] = v
          else
            logger.debug {"Pattern does not match '#{k}'"}
          end
        end

      end

      # Returns a hash of the group name to a param hash (param_key -> param_value)
      param_groups
    end

    def apply_config_maps(param_groups)
      # For each set of parameters grouped by name, add those parameters
      # to the config map with that name
      #
      kubeapi = KubeApi.new(namespace: kube_namespace,
                            token: kube_token,
                            api_url: kube_url)

      logger.debug { "Existing config maps: #{kubeapi.get_config_map_names}" }

      param_groups.each do |k, v|
        begin
          cm = kubeapi.get_config_map(k)
          logger.debug("Config map for #{k}: #{cm.inspect}")
          if v != cm.data.to_h.transform_keys! {|k| k.to_s }
            logger.info "Updating config map #{k} with params: #{v.inspect}}"
            cm.data = v
            kubeapi.update_config_map(cm)
          else
            logger.info "No changes needed for config map #{k} with params: #{v.inspect}}"
          end
        rescue Kubeclient::ResourceNotFoundError
          logger.info "Creating config map #{k} with params: #{v.inspect}}"
          kubeapi.create_config_map(k, v)
        end
      end
    end

  end
end
