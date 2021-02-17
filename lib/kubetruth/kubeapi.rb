require_relative 'logging'
require 'kubeclient'
require 'base64'

module Kubetruth
  class KubeApi

    include GemLogger::LoggerSupport

    attr_accessor :namespace

    MANAGED_LABEL_KEY = "app.kubernetes.io/managed-by"
    MANAGED_LABEL_VALUE = "kubetruth"
    def initialize(namespace: nil, token: nil, api_url: nil)
      namespace_path = '/var/run/secrets/kubernetes.io/serviceaccount/namespace'
      ca_path = '/var/run/secrets/kubernetes.io/serviceaccount/ca.crt'
      token_path = '/var/run/secrets/kubernetes.io/serviceaccount/token'

      @namespace = namespace || File.read(namespace_path).chomp
      @labels = {MANAGED_LABEL_KEY => MANAGED_LABEL_VALUE}

      @auth_options = {}
      if token
        @auth_options[:bearer_token] = token
      elsif File.exist?(token_path)
        @auth_options[:bearer_token_file] = token_path
      end

      @ssl_options = {}
      if File.exist?(ca_path)
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

    def ensure_namespace
      begin
        client.get_namespace(namespace)
      rescue Kubeclient::ResourceNotFoundError
        ns = Kubeclient::Resource.new
        ns.metadata = {}
        ns.metadata.name = namespace
        ns.metadata.labels = @labels
        client.create_namespace(ns)
      end
    end

    def under_management?(resource)
      resource.metadata.labels[MANAGED_LABEL_KEY] == MANAGED_LABEL_VALUE
    end

    def get_config_map_names
      client.get_config_maps(namespace: namespace).collect(&:metadata).collect(&:name)
    end

    def get_config_map(name)
      resource = client.get_config_map(name, namespace)
      resource
    end

    def create_config_map(name, data)
      resource = Kubeclient::Resource.new
      resource.metadata = {}
      resource.metadata.name = name
      resource.metadata.namespace = @namespace
      resource.metadata.labels = @labels
      resource.data = data
      client.create_config_map(resource)
    end

    def update_config_map(name, data)
      resource = client.get_config_map(name, namespace)
      resource.metadata.labels = resource.metadata.labels.to_h.merge(@labels)
      resource.data = data
      client.update_config_map(resource)
    end

    def delete_config_map(name)
      client.delete_config_map(name, namespace)
    end

    def get_secret_names
      client.get_secrets(namespace: namespace).collect(&:metadata).collect(&:name)
    end

    def secret_hash(resource)
      Hash[resource.data.to_h.collect {|k, v| [k, Base64.decode64(v)]}]
    end

    def get_secret(name)
      resource = client.get_secret(name, namespace)
      resource
    end

    def create_secret(name, data)
      resource = Kubeclient::Resource.new
      resource.metadata = {}
      resource.metadata.name = name
      resource.metadata.namespace = @namespace
      resource.metadata.labels = @labels
      resource.stringData = data
      client.create_secret(resource)
    end

    def update_secret(name, data)
      resource = client.get_secret(name, namespace)
      resource.metadata.labels = resource.metadata.labels.to_h.merge(@labels)
      resource.stringData = data
      client.update_secret(resource)
    end

    def delete_secret(name)
      client.delete_secret(name, namespace)
    end

  end
end
