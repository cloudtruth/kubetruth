require 'active_support/core_ext/hash/keys'
require 'active_support/core_ext/string/inflections'
require 'active_support/json'
require 'yaml'

require_relative 'kubetruth/logging'
require_relative 'kubetruth/sigdump'

# Need to setup logging before loading any other files
Kubetruth::Logging.setup_logging(level: :info, color: false)

module Kubetruth
  VERSION = YAML.load(File.read(File.expand_path('../.app.yml', __dir__)),
                      filename: File.expand_path('../.app.yml', __dir__),
                      symbolize_names: true)[:version]

  class Error < StandardError; end
end
