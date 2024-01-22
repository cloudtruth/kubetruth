require 'kubeclient'
require 'async/semaphore'

module Kubetruth
  class KubeApi

    include GemLogger::LoggerSupport

    @@instance = nil

    def self.configure(namespace:, token:, api_url:)
      @@instance = self.new(namespace: namespace, token: token, api_url: api_url)
    end

    def self.instance
      raise ArgumentError.new("KubeApi has not been configured") if @@instance.nil?
      return @@instance
    end

    attr_accessor :namespace

    NAMESPACE_PATH = '/var/run/secrets/kubernetes.io/serviceaccount/namespace'
    CA_PATH = '/var/run/secrets/kubernetes.io/serviceaccount/ca.crt'
    TOKEN_PATH = '/var/run/secrets/kubernetes.io/serviceaccount/token'

    MANAGED_LABEL_KEY = "app.kubernetes.io/managed-by"
    MANAGED_LABEL_VALUE = "kubetruth"
    # an alternate label in case user already uses managed-by, we may want to
    # make it more specific for patch only behavior (vs full ownership)
    EDITABLE_LABEL_KEY = "app.kubernetes.io/editable-by"
    EDITABLE_LABEL_VALUE = "kubetruth"

    def initialize(namespace: nil, token: nil, api_url: nil)

      @namespace = namespace.present? ? namespace : File.read(NAMESPACE_PATH).chomp

      @auth_options = {}
      if token
        @auth_options[:bearer_token] = token
      elsif File.exist?(TOKEN_PATH)
        @auth_options[:bearer_token_file] = TOKEN_PATH
      end

      @ssl_options = {}
      if File.exist?(CA_PATH)
        @ssl_options[:ca_file] = CA_PATH
      end

      @api_url = api_url || 'https://kubernetes.default.svc'
      @api_clients = {}
      @namespace_mutex = Async::Semaphore.new(1)
    end

    def api_url(api)
      api.present? ? "#{@api_url}/apis/#{api}" : @api_url
    end

    def api_client(api: nil, version: nil)
      key = {api: api_url(api), version: version.blank? ? "v1" : version}
      @api_clients[key] ||= Kubeclient::Client.new(
        key[:api],
        key[:version],
        auth_options: @auth_options,
        ssl_options:  @ssl_options
      )
    end

    def client
      api_client(api: nil, version: "v1")
    end

    def crd_client
      api_client(api: "kubetruth.cloudtruth.com", version: "v1")
    end

    def apiVersion_client(apiVersion)
      apiVersion ||= "v1"
      api_details = apiVersion.split("/")
      api_details.insert(0, nil) if api_details.size == 1
      api_client(api: api_details[0], version: api_details[1])
    end

    def ensure_namespace(ns = namespace)
      @namespace_mutex.acquire do
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
    end

    def under_management?(resource)
      labels = resource&.[]("metadata")&.[]("labels")
      return false if labels.nil?
      result = labels[MANAGED_LABEL_KEY] == MANAGED_LABEL_VALUE
      result ||= labels[EDITABLE_LABEL_KEY] == EDITABLE_LABEL_VALUE
      return result
    end

    def set_managed(resource)
      resource["metadata"] ||= {}
      resource["metadata"]["labels"] ||= {}
      resource["metadata"]["labels"][MANAGED_LABEL_KEY] = MANAGED_LABEL_VALUE
    end


    def copy_managed(source, dest)
      source_labels = source&.[]("metadata")&.[]("labels") || {}
      dest["metadata"] ||= {}
      dest["metadata"]["labels"] ||= {}
      dest["metadata"]["labels"][MANAGED_LABEL_KEY] = MANAGED_LABEL_VALUE if source_labels[MANAGED_LABEL_KEY] == MANAGED_LABEL_VALUE
      dest["metadata"]["labels"][EDITABLE_LABEL_KEY] = EDITABLE_LABEL_VALUE if source_labels[EDITABLE_LABEL_KEY] == EDITABLE_LABEL_VALUE
    end

    def get_resource(resource_name, name, namespace: nil, apiVersion: nil)
      apiVersion_client(apiVersion).get_entity(resource_name, name, namespace || self.namespace)
    end

    def apply_resource(resource)
      resource = Kubeclient::Resource.new(resource) if resource.is_a? Hash
      resource_name = resource.kind.downcase.pluralize
      apiVersion_client(resource.apiVersion).apply_entity(resource_name, resource, field_manager: "kubetruth")
    end

    def get_project_mappings
      mappings = crd_client.get_project_mappings
      grouped_mappings = {}
      mappings.each do |r|
        ns = r.metadata.namespace
        name = r.metadata.name
        mapping = r.spec.to_h
        mapping[:name] = name
        grouped_mappings[ns] ||= {}
        grouped_mappings[ns][name] = mapping
      end
      grouped_mappings
    end

    def watch_project_mappings(&block)
      existing = crd_client.get_project_mappings
      collection_version = existing.resourceVersion
      crd_client.watch_project_mappings(resource_version: collection_version, &block)
    end

  end
end
