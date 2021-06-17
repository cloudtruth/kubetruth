require 'kubeclient'

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

      @namespace = namespace.present? ? namespace : File.read(namespace_path).chomp

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
      @crd_api_url = "#{@api_url}/apis/kubetruth.cloudtruth.com"
    end

    def client
      @client ||= Kubeclient::Client.new(
          @api_url,
          'v1',
          auth_options: @auth_options,
          ssl_options:  @ssl_options
      )
    end

    def crdclient
      @crdclient ||= Kubeclient::Client.new(
        @crd_api_url,
        'v1',
        auth_options: @auth_options,
        ssl_options:  @ssl_options
      )
    end

    def ensure_namespace(ns = namespace)
      begin
        client.get_namespace(ns)
      rescue Kubeclient::ResourceNotFoundError
        newns = Kubeclient::Resource.new
        newns.metadata = {}
        newns.metadata.name = ns
        set_managed(newns)
        client.create_namespace(newns)
      end
    end

    def under_management?(resource)
      labels = resource&.[]("metadata")&.[]("labels")
      labels.nil? ? false : resource["metadata"]["labels"][MANAGED_LABEL_KEY] == MANAGED_LABEL_VALUE
    end

    def set_managed(resource)
      resource["metadata"] ||= {}
      resource["metadata"]["labels"] ||= {}
      resource["metadata"]["labels"][MANAGED_LABEL_KEY] = MANAGED_LABEL_VALUE
    end

    def get_resource(resource_name, name, namespace=nil)
      client.get_entity(resource_name, name, namespace || self.namespace)
    end

    def apply_resource(resource)
      resource = Kubeclient::Resource.new(resource) if resource.is_a? Hash
      resource_name = resource.kind.downcase.pluralize
      client.apply_entity(resource_name, resource, field_manager: "kubetruth")
    end

    def get_project_mappings
      crdclient.get_project_mappings(namespace: namespace).collect(&:spec).collect(&:to_h)
    end

    def watch_project_mappings(&block)
      existing = crdclient.get_project_mappings(namespace: namespace)
      collection_version = existing.resourceVersion
      crdclient.watch_project_mappings(namespace: namespace, resource_version: collection_version, &block)
    end

  end
end
