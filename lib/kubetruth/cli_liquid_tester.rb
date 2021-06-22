require_relative 'cli_base'
require_relative 'template'

module Kubetruth
  class CLILiquidTester < CLIBase

    banner <<~EOF
      Allows one to experiment with liquid templates by evaluating the given
      template with the supplied variable context
    EOF

    option ["-v", "--variable"],
           'VAR', "variable=value to be used in evaluating the template",
           multivalued: true

    option ["-t", "--template"],
           'TMPL', "The template to evaluate"

    option ["-f", "--template-file"],
           'FILE', "A file containing the template. use '-' for stdin"

    def execute
      super

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
