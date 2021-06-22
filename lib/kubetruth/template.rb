require 'liquid'
require 'digest'
require 'base64'

module Kubetruth
  class Template

    include GemLogger::LoggerSupport

    class Error < ::StandardError
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

      def inspect
        {source: @source, parsed: @parsed}.inspect
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

      def to_yaml(str)
        str.to_yaml
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

        logger.debug do
          msg = "Evaluating template:\n"
          @source.to_s.lines.collect {|l| msg << (INDENT * 2) << l }
          msg << "\n" << INDENT << "with context:\n"
          kwargs.deep_stringify_keys.to_yaml.lines.collect {|l| msg << (INDENT * 2) << l }
          msg
        end

        result = @liquid.render!(*args, kwargs.stringify_keys, strict_variables: true, strict_filters: true)

        logger.debug do
          msg = "Rendered template:\n"
          result.lines.collect {|l| msg << (INDENT * 2) << l }
          msg
        end

        result

      rescue Liquid::Error => e
        indent = "  "
        msg = "Template failed to render:\n"
        @source.lines.each {|l| msg << (indent * 2) << l }
        msg << indent << "with error message:\n" << (indent * 2) << "#{e.message}"
        if e.is_a?(Liquid::UndefinedVariable)
          msg << "\n" << indent << "and variable context:\n"
          msg << (indent * 2) << kwargs.inspect
        end
        raise Error, msg

        raise Error, "Template failed to render: #{e.message}"
      end
    end

    def to_s
      @source
    end

  end
end
