require "bundler/setup"
require "kubetruth"
require "kubetruth/logging"
require "open3"

if ENV['CI']
  require 'coveralls'
  Coveralls.wear!
else
  require 'simplecov'
  SimpleCov.start
end

require 'vcr'
require 'webmock/rspec'

def fixture_dir
  @fixture_dir ||= File.expand_path("../fixtures", __FILE__)
end

# Monkey patch VCR so we can do a regexp replace for parameter values (multiple
# different strings matching a pattern in single response body)
class VCR::HTTPInteraction::HookAware
  def filter!(text, replacement_text)
    # replacement -> text when loading a fixture
    if replacement_text.is_a?(Regexp)
      replacement_text = text
      return self if replacement_text.empty?
    end

    # text -> replacement when writing out a fixture
    if text.is_a?(Regexp)
      return self if text == //
    else
      text = text.to_s
      return self if text.empty?
    end

    filter_object!(self, text, replacement_text)
  end

  private

  def filter_object!(object, text, replacement_text)
    if object.respond_to?(:gsub)

      if text.is_a?(Regexp)
        object.gsub!(text, replacement_text) if object.match?(text)
      else
        begin
        object.gsub!(text, replacement_text) if object.include?(text)
        rescue
          raise
        end

      end
    elsif Hash === object
      filter_hash!(object, text, replacement_text)
    elsif object.respond_to?(:each)
      # This handles nested arrays and structs
      object.each { |o| filter_object!(o, text, replacement_text) }
    end

    object
  end
end

VCR.configure do |c|
  c.cassette_library_dir = "#{fixture_dir}/vcr"
  c.hook_into :webmock
  c.configure_rspec_metadata!
  c.filter_sensitive_data('<BEARER_TOKEN>') do |interaction|
    auths = interaction.request.headers['Authorization'].first
    if (match = auths.match /^Bearer\s+([^,\s]+)/ )
      match.captures.first
    end
  end

  string_with_escapes = '"((\\\\.|[^\"])*)"'
  c.filter_sensitive_data('"parameterValue":"<PARAM_VALUE>"') { /"parameterValue":#{string_with_escapes}/ }
  c.filter_sensitive_data('"CT_API_KEY":"<API_KEY>"') { /"CT_API_KEY":#{string_with_escapes}/ }
end


RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  # config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before(:each) do
    Kubetruth::Logging.testing = true
    Kubetruth::Logging.setup_logging(level: :debug, color: false)
    Kubetruth::Logging.clear
  end

  config.after(:each) do |example|
    if example.exception
      puts
      puts "Debug log for failing spec: #{example.full_description}"
      puts Kubetruth::Logging.contents
      puts
    end
  end

end

require "test_construct/rspec_integration"

RSpec::Matchers.define :be_line_width_for_cli do |name|
  match do |actual|
    @actual = []
    @expected = []
    actual.lines.each {|l| @actual << l if l.chomp.size > 80}
    !(actual.nil? || actual.empty?) && @actual.size == 0
  end

  diffable

  failure_message do |actual|
    maybe_name = name.nil? ? "" : "[subcommand=#{name}] "
    if @actual.size == 0
      "#{maybe_name}No lines in output"
    else
      "#{maybe_name}Some lines are longer than standard terminal width"
    end
  end
end

require 'stringio'

module IoTestHelpers
  def simulate_stdin(*inputs, &block)
    io = StringIO.new
    inputs.flatten.each { |str| io.puts(str) }
    io.rewind

    actual_stdin, $stdin = $stdin, io
    yield
  ensure
    $stdin = actual_stdin
  end

  def sysrun(*args, output_on_fail: true, allow_fail: false, stdin_data: nil)
    args = args.compact
    output, status = Open3.capture2e(*args, stdin_data: stdin_data)
    puts output if output_on_fail && status.exitstatus != 0
    if ! allow_fail
      expect(status.exitstatus).to eq(0), "#{args.join(' ')} failed: #{output}"
    end
    return output
  end

end

include IoTestHelpers

