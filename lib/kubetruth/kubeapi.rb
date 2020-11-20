require_relative 'logging'
require 'kubeclient'

module Kubetruth
  class KubeApi

    include GemLogger::LoggerSupport

    attr_accessor :namespace

    def initialize(namespace: nil, token: nil, api_url: nil, ca: nil)
      namespace_path = '/var/run/secrets/kubernetes.io/serviceaccount/namespace'
      ca_path = '/var/run/secrets/kubernetes.io/serviceaccount/ca.crt'
      token_path = '/var/run/secrets/kubernetes.io/serviceaccount/token'

      @namespace = namespace || File.read(namespace_path).chomp

      @auth_options = {}
      if token
        @auth_options[:bearer_token] = token
      elsif File.exist?(token_path)
        @auth_options[:bearer_token_file] = token_path
      end

      @ssl_options = {}
      if ca
        @ssl_options[:ca] = ca
      elsif File.exist?(ca_path)
        @ssl_options[:ca_file] = ca_path
      end

      @api_url = api_url || 'https://kubernetes.default.svc'
    end

    def client
      @client ||= Kubeclient::Client.new(
          @api_url,
          'v1',
          auth_options: @auth_options,
          ssl_options:  @ssl_options
      )
    end

    def get_config_map_names
      client.get_config_maps(namespace: namespace).collect(&:metadata).collect(&:name)
    end

    def get_config_map(name)
      client.get_config_map(name, namespace)
    end

    def create_config_map(name, data)
      cm = Kubeclient::Resource.new
      cm.metadata = {}
      cm.metadata.name = name
      cm.metadata.namespace = @namespace
      cm.metadata.data = data
      client.create_config_map(cm)
    end

    def update_config_map(cm)
      client.update_config_map(cm)
    end

  end
end
