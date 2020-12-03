require_relative 'logging'

module Kubetruth
  Parameter = Struct.new(:key, :value, :secret, :original_key, keyword_init: true)
end
