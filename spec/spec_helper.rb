require "bundler/setup"
ENV['CLOUDTRUTH_API_KEY'] ||= 'fake_api_key'
require "kubetruth"

require "open3"

codecov = ENV['CI'] && ENV['CODECOV_TOKEN']
require 'codecov' if codecov

require 'simplecov'
SimpleCov.formatter (codecov ? SimpleCov::Formatter::Codecov : SimpleCov::Formatter::HTMLFormatter)
SimpleCov.enable_for_subprocesses true
SimpleCov.at_fork do |pid|
  # This needs a unique name so it won't be ovewritten
  SimpleCov.command_name "#{SimpleCov.command_name} (subprocess: #{pid})"
  # be quiet, the parent process will be in charge of output and checking coverage totals
  SimpleCov.print_error_status = false
  SimpleCov.formatter (codecov ? SimpleCov::Formatter::Codecov : SimpleCov::Formatter::HTMLFormatter)
  SimpleCov.minimum_coverage 0
  # start
  SimpleCov.start do
    add_filter 'spec'
    add_filter '/client/'
  end
end
SimpleCov.start do
  add_filter 'spec'
  add_filter '/client/'
end

require 'vcr'
require 'webmock/rspec'

def fixture_dir
  @fixture_dir ||= File.expand_path("../fixtures", __FILE__)
end

def default_root_spec
  default_root_spec = YAML.load_file(File.expand_path("../helm/kubetruth/values.yaml", __dir__)).deep_symbolize_keys
  default_root_spec[:projectMappings][:root]
end

def logger
  ::Logging.logger.root
end

VCR.configure do |c|
  c.cassette_library_dir = "#{fixture_dir}/vcr"
  c.hook_into :webmock
  c.configure_rspec_metadata!
  c.filter_sensitive_data('<TOKEN>') do |interaction|
    auths = interaction.request.headers['Authorization'].first
    if (match = auths.match /^[^\s]+\s+([^,\s]+)/ )
      match.captures.first
    end
  end
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
    if ENV['DEBUG'] || example.exception
      puts
      puts "Debug log for failing spec: #{example.full_description}"
      puts Kubetruth::Logging.contents
      puts
    end
  end

end

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

module CLITestHelpers

  def all_usage(clazz, path=[])
    Enumerator.new do |y|
      obj = clazz.new("")
      path << clazz.name.split(":").last if path.empty?
      cmd_path = path.join(" -> ")
      y << {name: cmd_path, usage: obj.help}

      clazz.recognised_subcommands.each do |sc|
        sc_clazz = sc.subcommand_class
        sc_name = sc.names.first
        all_usage(sc_clazz, path + [sc_name]).each {|sy| y << sy}
      end
    end
  end

end

include CLITestHelpers

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

