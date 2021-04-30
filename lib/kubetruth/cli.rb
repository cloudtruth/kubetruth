require_relative 'logging'
# Need to setup logging before loading any other files
Kubetruth::Logging.setup_logging(level: :info, color: false)

require_relative 'etl'
require 'clamp'

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
           :flag, "perform a dry run",
           default: false

    option ["-q", "--quiet"],
           :flag, "suppress output",
           default: false

    option ["-d", "--debug"],
           :flag, "debug output",
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

      etl = ETL.new(ct_context: ct_context, kube_context: kube_context, dry_run: dry_run?)

      etl.with_polling(polling_interval) do
        etl.apply
      end

    end

  end
end

# Hack to make clamp usage less of a pain to get long lines to fit within a
# standard terminal width
class Clamp::Help::Builder

  def word_wrap(text, line_width: 80)
    text.split("\n").collect do |line|
      line.length > line_width ? line.gsub(/(.{1,#{line_width}})(\s+|$)/, "\\1\n").strip.split("\n") : line
    end.flatten
  end

  def string
    indent_size = 4
    indent = " " * indent_size
    StringIO.new.tap do |out|
      lines.each do |line|
        case line
        when Array
          out << indent
          out.puts(line[0])
          formatted_line = line[1].gsub(/\((default|required)/, "\n\\0")
          word_wrap(formatted_line, line_width: (80 - indent_size * 2)).each do |l|
            out << (indent * 2)
            out.puts(l)
          end
        else
          out.puts(line)
        end
      end
    end.string
  end

end
