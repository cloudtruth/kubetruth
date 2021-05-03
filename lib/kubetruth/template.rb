require_relative 'logging'
require 'liquid'

module Kubetruth
  class Template

    include GemLogger::LoggerSupport

    class Error < ::StandardError
    end

    module CustomLiquidFilters

      # From kubernetes error message
      DNS_VALIDATION_RE = /^[a-z0-9]([-a-z0-9]*[a-z0-9])?(\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*$/
      ENV_VALIDATION_RE = /^[A-Z_][A-Z0-9_]*$/

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

    def render(**kwargs)
      begin
        logger.debug { "Evaluating template '#{@source}' with context: #{kwargs.inspect}" }
        @liquid.render!(kwargs.stringify_keys, strict_variables: true, strict_filters: true)
      rescue Liquid::Error => e
        msg = "Invalid template '#{@source}': #{e.message}"
        msg << ", context: #{kwargs.inspect}" if e.is_a?(Liquid::UndefinedVariable)
        raise Error.new(msg)
      end
    end

    def to_s
      @source
    end

  end
end
