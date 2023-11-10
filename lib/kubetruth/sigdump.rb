require 'sigdump/setup'
require 'async'

# Adds the reporting of async tasks during a sigdump
module Sigdump
  class << self

    def dump_async(task, io)
      io.write "  Async Task #{task.description} status=#{task.status}\n"
      if task.backtrace
        task.backtrace.each {|bt|
          io.write "      #{bt}\n"
        }
      end
      io.flush
    end

    alias_method :original_dump_backtrace, :dump_backtrace
    def dump_backtrace(thread, io)
      original_dump_backtrace(thread, io)

      ObjectSpace.each_object(Async::Task) do |task|
        dump_async(task, io) if task
      end

    end

  end
end
