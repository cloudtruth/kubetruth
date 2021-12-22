require 'liquid'
require 'digest'
require 'base64'
require_relative 'ctapi'

module Kubetruth
  class Template

    include GemLogger::LoggerSupport

    class Error < ::Kubetruth::Error
    end

    class TemplateHashDrop < Liquid::Drop

      attr_reader :source

      def initialize(template_hash)
        @source = template_hash.stringify_keys
        @parsed = {}
      end

      def liquid_method_missing(key)
        if @source.has_key?(key)
          if @source[key].is_a?(String)
            @parsed[key] ||= Template.new(@source[key])
            @parsed[key].render(@context)
          else
            @parsed[key] ||= @source[key]
            @parsed[key]
          end
        else
          super
        end
      end

      def encode_with(coder)
        coder.represent_map(nil, @source)
      end

    end

    class TemplatesDrop < Liquid::Drop

      def initialize(project:, environment:)
        @project = project
        @environment = environment
      end

      def names
        CtApi.instance.template_names(project: @project)
      end

      def liquid_method_missing(key)
        CtApi.instance.template(key, project: @project, environment: @environment)
      end

    end

    module CustomLiquidFilters

      # From kubernetes error message
      DNS_VALIDATION_RE = /^[a-z0-9]([-a-z0-9]*[a-z0-9])?(\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*$/
      ENV_VALIDATION_RE = /^[A-Z_][A-Z0-9_]*$/
      KEY_VALIDATION_RE = /^[\w\.\-]*$/

      def dns_safe(str)
        return str if str =~ DNS_VALIDATION_RE
        result = str.to_s.downcase.gsub(/[^-.a-z0-9)]+/, '-')
        result = result.gsub(/(^[^a-z0-9]+)|([^a-z0-9]+$)/, '')
        result
      end

      def env_safe(str)
        return str if str =~ ENV_VALIDATION_RE
        result = str.upcase
        result = result.gsub(/(^\W+)|(\W+$)/, '')
        result = result.gsub(/\W+/, '_')
        result = result.sub(/^\d/, '_\&')
        result
      end

      # Kubernetes validation: a valid config key must consist of alphanumeric
      # characters, '-', '_' or '.'
      def key_safe(str)
        return str if str =~ KEY_VALIDATION_RE
        str.gsub(/[^\w\.\-]+/, '_')
      end

      def indent(str, count)
        result = ""
        str.lines.each do |l|
          result << (" " * count) << l
        end
        result
      end

      def nindent(str, count)
        indent("\n" + str, count)
      end

      def stringify(str)
        str.to_s.to_json
      end

      def to_yaml(str, options = {})
        options = {} unless options.is_a?(Hash)
        result = str.to_yaml
        result = result[4..-1] if options['no_header']
        result
      end

      def to_json(str)
        str.to_json
      end

      def sha256(data)
        Digest::SHA256.hexdigest(data)
      end

      def encode64(str)
        Base64.strict_encode64(str)
      end

      def decode64(str)
        Base64.strict_decode64(str)
      end

      def deflate(hash, delimiter='.')
        result = {}

        hash.each do |k, v|
          case v
            when String, Numeric, TrueClass, FalseClass
              result[k] = v
            when Array
              result[k] = JSON.generate(v)
            when Hash
              m = deflate(v, delimiter)
              m.each do |mk, mv|
                result["#{k}#{delimiter}#{mk}"] = mv
              end
            else
              result[k] = v.to_s
          end
        end

        return result
      end

      def inflate(map, delimiter='\.')
        result = {}
        map.each do |k, v|
          path = k.split(/#{delimiter}/)
          scoped = result
          path.each_with_index do |p, i|
            if i == (path.size - 1)
              scoped[p] = v
            else
              scoped[p] ||= {}
              scoped = scoped[p]
            end
          end
        end
        result
      end

      def typify(data, parser="json")
        case data
          when Hash
            Hash[data.collect {|k,v| [k, typify(v)] }]
          when Array
            data.collect {|v| typify(v) }
          when /^\s*\[.*\]\s*$/, /^\s*\{.*\}\s*$/
            parsed = case parser
            when /json/i
              JSON.load(data)
            when /ya?ml/i
              YAML.load(data)
            else
              raise "Invalid typify parser"
            end
            typify(parsed)
          when /^[0-9]+$/
            data.to_i
          when /^[0-9\.]+$/
            data.to_f
          when /true|false/
            data == "true"
          else
            data
        end
      end

      def merge(lhs_map, rhs_map)
        lhs_map.merge(rhs_map)
      end

      REGEXP_FLAGS = {
        'i' => Regexp::IGNORECASE,
        'm' => Regexp::MULTILINE,
        'e' => Regexp::EXTENDED
      }

      def re_replace(string, pattern, replacement, flags="")
        allflags = flags.chars.inject(0) {|sum, n| sum | REGEXP_FLAGS[n] }
        string.gsub(Regexp.new(pattern, allflags), replacement)
      end

    end

    Liquid::Template.register_filter(CustomLiquidFilters)

    attr_reader :source

    def initialize(template_source)
      @source = template_source
      begin
        @liquid = Liquid::Template.parse(@source, error_mode: :strict)
      rescue Liquid::Error => e
        raise Error.new(e.message)
      end
    end

    INDENT = (" " * 2)

    def render(*args, **kwargs)
      begin

        # TODO: fix secrets hardcoding here
        secrets = kwargs[:secrets] || {}
        debug_kwargs = nil

        logger.debug do
          # TODO: fix secrets hardcoding here
          debug_kwargs ||= kwargs.merge(secrets: Hash[secrets.collect {|k, v| [k, "<masked:#{k}>"] }])
          msg = "Evaluating template:\n"
          @source.to_s.lines.collect {|l| msg << (INDENT * 2) << l }
          msg << "\n" << INDENT << "with context:\n"
          debug_kwargs.deep_stringify_keys.to_yaml.lines.collect {|l| msg << (INDENT * 2) << l }
          msg
        end

        result = @liquid.render!(*args, kwargs.stringify_keys, strict_variables: true, strict_filters: true)

        logger.debug do
          debug_kwargs ||= kwargs.merge(secrets: Hash[secrets.collect {|k, v| [k, "<masked:#{k}>"] }])
          # we only ever have to sub base64 encoded in this debug block
          both_secrets = secrets.merge(Hash[secrets.collect {|k, v| ["#{k}_base64", Base64.strict_encode64(v)]}])

          msg = "Rendered template:\n"
          r = result.dup

          # Handle multiline secrets that may have had their indentation changed
          # (e.g. nindent for a cert) by splitting on whitespace and only
          # subbing the non-whitespace parts from the template
          both_secrets.each do |k, v|
            v.split(/\s+/).delete_if(&:blank?).each do |part|
              r.gsub!(part, "<masked:#{k}>")
            end
          end

          r.lines.collect {|l| msg << (INDENT * 2) << l }
          msg
        end

        result

      rescue StandardError => e
        msg = "Template failed to render with error message:\n"
        msg << (INDENT * 2) << e.message << "\n"
        if e.is_a?(Liquid::UndefinedVariable)
          msg << INDENT << "and variable context:\n"
          debug_kwargs ||= kwargs.merge(secrets: Hash[secrets.collect {|k, v| [k, "<masked:#{k}>"] }])
          debug_kwargs.deep_stringify_keys.to_yaml.lines.collect {|l| msg << (INDENT * 2) << l }
        end
        msg << INDENT << "and template source:\n"
        @source.lines.each {|l| msg << (INDENT * 2) << l }
        raise Error, msg
      end
    end

    def to_s
      @source
    end

    def encode_with(coder)
      coder.represent_scalar(nil, @source)
    end

  end
end
