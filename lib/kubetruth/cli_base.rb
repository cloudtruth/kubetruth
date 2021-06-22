require 'clamp'
require_relative 'clamp_help_formatter'

module Kubetruth
  class CLIBase < Clamp::Command

    include GemLogger::LoggerSupport

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
           :flag, "show version" do
      logger.info "Version #{VERSION}"
      exit(0)
    end

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
    end

  end
end
