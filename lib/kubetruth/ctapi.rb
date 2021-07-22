require 'uri'
require "cloudtruth-client"
require_relative 'parameter'

module Kubetruth
  class CtApi

    @@instance = nil

    def self.configure(api_key:, api_url:)
      @@instance = self.new(api_key: api_key, api_url: api_url)
    end

    def self.instance
      raise ArgumentError.new("CtApi has not been configured") if @@instance.nil?
      return @@instance
    end

    include GemLogger::LoggerSupport

    attr_reader :client, :apis

    class ApiConfiguration < CloudtruthClient::Configuration

      # The presence of JWTAuth in the hardcoded default auth_settings was
      # overwriting our set api key with nil in
      # CloudtruthClient:„:ApiClient#update_params_for_auth!
      def auth_settings
        {
          'ApiKeyAuth' =>
            {
              type: 'api_key',
              in: 'header',
              key: 'Authorization',
              value: api_key_with_prefix('ApiKeyAuth')
            }
        }
      end

    end

    def initialize(api_key:, api_url:)
      @api_key = api_key
      @api_url = api_url
      uri = URI(@api_url)
      config = ApiConfiguration.new
      config.server_index = nil
      config.scheme = uri.scheme
      host_port = uri.host
      host_port << ":#{uri.port}" unless [80, 443].include?(uri.port)
      config.host = host_port
      config.base_path = uri.path
      config.api_key = {'ApiKeyAuth' => api_key}
      config.api_key_prefix = {'ApiKeyAuth' => "Api-Key"}
      config.logger = logger
      # config.debugging = logger.debug?
      @client = CloudtruthClient::ApiClient.new(config)
      @client.user_agent = "kubetruth/#{Kubetruth::VERSION}"
      @apis = {
        api: CloudtruthClient::ApiApi.new(@client),
        environments: CloudtruthClient::EnvironmentsApi.new(@client),
        projects: CloudtruthClient::ProjectsApi.new(@client)
      }
    end

    def environments
      @environments ||= begin
        result = apis[:environments].environments_list
        logger.debug{"Environments query result: #{result.inspect}"}
        Hash[result&.results&.collect {|r| [r.name, r.id]}]
      end
    end

    def environment_names
      environments.keys
    end

    def environment_id(environment)
      env_id = self.environments[environment]

      # retry in case environments have been updated upstream since we cached
      # them
      if env_id.nil?
        logger.debug {"Unknown environment, retrying after clearing cache"}
        @environments = nil
        env_id = self.environments[environment]
      end

      raise Kubetruth::Error.new("Unknown environment: #{environment}") unless env_id
      env_id.to_s
    end

    def projects
      result = apis[:projects].projects_list
      logger.debug{"Projects query result: #{result.inspect}"}
      Hash[result&.results&.collect {|r| [r.name, r.id]}]
    end

    def project_names
      projects.keys
    end

    def parameters(project:, environment: "default")
      env_id = environment_id(environment)
      proj_id = projects[project]
      result = apis[:projects].projects_parameters_list(proj_id, environment: env_id)
      logger.debug do
        cleaned = result&.to_hash&.deep_dup
        cleaned&.[](:results)&.each do |param|
          if param[:secret]
            param[:values].each do |k, v|
              v[:value] = "<masked>" unless v.nil?
            end
          end
        end
        "Parameters query result: #{cleaned.inspect}"
      end
      result&.results&.collect do |param|
        # values is keyed by url, but we forced it to only have a single entry
        # for the supplied environment
        Kubetruth::Parameter.new(key: param.name, value: param.values.values.first&.value, secret: param.secret)
      end
    end

  end
end
