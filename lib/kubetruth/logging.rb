require 'logging'
require 'gem_logger'

module Kubetruth
  module Logging

    module GemLoggerConcern
      extend ActiveSupport::Concern

      def logger
        ::Logging.logger[self.class]
      end

      module ClassMethods
        def logger
          ::Logging.logger[self]
        end
      end
    end

    def self.init_logger
      return if @initialized
      @initialized = true

      ::Logging.format_as :inspect
      ::Logging.backtrace true

      ::Logging.color_scheme(
          'bright',
          lines: {
              debug: :green,
              info: :default,
              warn: :yellow,
              error: :red,
              fatal: [:white, :on_red]
          },
          date: :blue,
          logger: :cyan,
          message: :magenta
      )

      ::Logging.logger.root.level = :info
      GemLogger.configure do |config|
        config.default_logger = ::Logging.logger.root
        config.logger_concern = Logging::GemLoggerConcern
      end
    end


    def self.testing
      @testing
    end

    def self.testing=(t)
      @testing = t
    end

    def self.sio
      ::Logging.logger.root.appenders.find {|a| a.name == 'sio' }
    end

    def self.contents
      sio&.sio&.to_s
    end

    def self.clear
      sio&.clear
    end

    def self.setup_logging(level: :info, color: true)
      init_logger

      ::Logging.logger.root.level = level
      appenders = []
      detail_pattern = '[%d] %-5l %c{1} %m\n'

      pattern_options = {
          pattern: detail_pattern
      }
      if color
        pattern_options[:color_scheme] = 'bright'
      end

      if self.testing

        appender = ::Logging.appenders.string_io(
            'sio',
            layout: ::Logging.layouts.pattern(pattern_options)
        )
        appenders << appender

      else

        appender = ::Logging.appenders.stdout(
            'stdout',
            layout: ::Logging.layouts.pattern(pattern_options)
        )
        appenders << appender

      end

      ::Logging.logger.root.appenders = appenders
    end

  end

end
