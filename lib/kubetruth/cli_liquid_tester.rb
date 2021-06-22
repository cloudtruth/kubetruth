require 'clamp'
require_relative 'template'
require_relative 'clamp_help_formatter'

module Kubetruth
  class CLILiquidTester < Clamp::Command

    include GemLogger::LoggerSupport

    option ["-v", "--variable"],
           'VAR', "variable=value to be used in evaluating the template",
           multivalued: true

    option ["-t", "--template"],
           'TMPL', "The template to evaluate"

    option ["-f", "--template-file"],
           'FILE', "A file containing the template. use '-' for stdin"

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

      tmpl = template if template.present?
      if template_file.present?
        tmpl ||= (template_file == "-") ? $stdin.read : File.read(template_file)
      end

      signal_usage_error("No template supplied") if tmpl.blank?

      variables = {}
      variable_list.each do |tv|
        k, v = tv.split("=")
        v = YAML.load(v)
        logger.debug("Variable '#{k}' = #{v.inspect}")
        variables[k] = v
      end

      puts Template.new(tmpl).render(**variables)
    end
  end
end
