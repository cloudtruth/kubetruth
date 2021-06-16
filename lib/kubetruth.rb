require 'active_support/core_ext/hash/keys'
require 'active_support/core_ext/string/inflections'
# prevent our use of ActiveSupport causing an error with json adapters
require 'active_support/json'

require_relative 'kubetruth/logging'
# Need to setup logging before loading any other files
Kubetruth::Logging.setup_logging(level: :info, color: false)

require_relative "kubetruth/version"

module Kubetruth
  class Error < StandardError; end
end
