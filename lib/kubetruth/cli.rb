require 'clamp'
require_relative 'project'
require_relative 'etl'
require_relative 'clamp_help_formatter'

module Kubetruth
  class CLI < Clamp::Command

    include GemLogger::LoggerSupport

    banner <<~EOF
      Scans cloudtruth parameters for `name-pattern`, using the `name` match as
      the name of the kubernetes config_map/secrets resource to apply those
      values to
    EOF

    option "--environment",
           'ENV', "The cloudtruth environment",
           environment_variable: 'CT_ENV',
           default: "default"

    option "--organization",
           'ORG', "The cloudtruth organization"

    option "--api-key",
           'APIKEY', "The cloudtruth api key",
           environment_variable: 'CLOUDTRUTH_API_KEY',
           required: true

    option "--kube-namespace",
           'NAMESPACE', "The kubernetes namespace. Defaults to runtime namespace when run in kube"

    option "--kube-token",
           'TOKEN', "The kubernetes token to use for api. Defaults to mounted when run in kube"

    option "--kube-url",
           'ENDPOINT', "The kubernetes api url. Defaults to internal api endpoint when run in kube"

    option "--polling-interval", "INTERVAL", "the polling interval", default: 300 do |a|
      Integer(a)
    end

    option ["-n", "--dry-run"],
           :flag, "Perform a dry run",
           default: false

    option ["-q", "--quiet"],
           :flag, "Suppress output",
           default: false

    option ["-d", "--debug"],
           :flag, "Debug output",
           default: false

    option ["-c", "--[no-]color"],
           :flag, "colorize output (or not)  (default: $stdout.tty?)",
            default: true

    option ["-v", "--version"],
           :flag, "show version",
           default: false

    # TODO: option to map template to configmap?

    # hook into clamp lifecycle to force logging setup even when we are calling
    # a subcommand
    def parse(arguments)
      super

      level = :info
      level = :debug if debug?
      level = :error if quiet?
      Kubetruth::Logging.setup_logging(level: level, color: color?)
    end

    def execute
      if version?
        logger.info "Kubetruth Version #{VERSION}"
        exit(0)
      end

      ct_context = {
          organization: organization,
          environment: environment,
          api_key: api_key
      }
      kube_context = {
          namespace: kube_namespace,
          token: kube_token,
          api_url: kube_url
      }

      Project.ctapi_context = ct_context
      etl = ETL.new(kube_context: kube_context, dry_run: dry_run?)

      Signal.trap("HUP") do
        puts "Handling HUP signal - waking up ETL poller" # logger cant be called from trap
        etl.interrupt_sleep
      end

      etl.with_polling(polling_interval) do
        etl.apply
      end

    end

  end
end
