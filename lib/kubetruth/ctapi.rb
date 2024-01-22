require 'uri'
require "cloudtruth-client"
require_relative 'parameter'
require 'faraday-cookie_jar'
require 'async/semaphore'

module Kubetruth
  class CtApi
    include GemLogger::LoggerSupport

    @@config = nil
    @@ctapis = {}
    @@ctapis_mutex = Async::Semaphore.new(1)

    def self.configure(api_key:, api_url:)
      if api_key.nil? || api_url.nil?
        @@config = nil
        return
      end
      uri = URI(api_url)
      config = ApiConfiguration.new
      config.server_index = nil
      config.scheme = uri.scheme
      host_port = uri.host
      host_port << ":#{uri.port}" unless [80, 443].include?(uri.port)
      config.host = host_port
      config.base_path = uri.path
      config.api_key = {'ApiKeyAuth' => api_key}
      config.api_key_prefix = {'ApiKeyAuth' => "Api-Key"}
      config.logger = self.logger
      config.use(:cookie_jar, jar: HTTP::CookieJar.new) # supply the cookie jar so that the same one is used across all connections
      @@config = config
    end

    attr_reader :client, :apis, :environment, :tag

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

    # Factory methods to allow caching of CtApi instances through a single
    # polling cycle to mitigate costs of fetching all projects/environments for
    # ID lookup
    def self.create(environment: "default", tag: nil)
      @@ctapis_mutex.acquire do
        @@ctapis[[environment, tag]] ||= CtApi.new(environment: environment, tag: tag)
      end
    end

    def self.reset
      @@ctapis_mutex.acquire do
        @@ctapis = {}
      end
    end

    def initialize(environment: "default", tag: nil)
      @environments_mutex = Async::Semaphore.new(1)
      @projects_mutex = Async::Semaphore.new(1)
      @templates_mutex = Async::Semaphore.new(1)

      raise ArgumentError.new("CtApi has not been configured") if @@config.nil?

      @environment = environment
      @tag = tag
      # config.debugging = logger.debug?
      @client = CloudtruthClient::ApiClient.new(@@config)
      @client.user_agent = "kubetruth/#{Kubetruth::VERSION}"
      @apis = {
        api: CloudtruthClient::ApiApi.new(@client),
        environments: CloudtruthClient::EnvironmentsApi.new(@client),
        projects: CloudtruthClient::ProjectsApi.new(@client)
      }
    end

    def environments
      @environments_mutex.acquire do
        @environments ||= begin
          result = apis[:environments].environments_list
          logger.debug{"Environments query result: #{result.inspect}"}
          Hash[result&.results&.collect {|r| [r.name, r.id]}]
        end
      end
    end

    def environment_names
      environments.keys
    end

    def environment_id(environment)
      env_id = self.environments[environment]
      raise Kubetruth::Error.new("Unknown environment: #{environment}") unless env_id
      env_id.to_s
    end

    def projects
      @projects_mutex.acquire do
        @projects ||= begin
          result = apis[:projects].projects_list
          logger.debug{"Projects query result: #{result.inspect}"}
          Hash[result&.results&.collect {|r| [r.name, r.id]}]
        end
      end
    end

    def project_names
      projects.keys
    end

    def project_id(project)
      project_id = projects[project]
      raise Kubetruth::Error.new("Unknown project: #{project}") unless project_id
      project_id.to_s
    end

    def parameters(project:)
      proj_id = project_id(project)
      opts = {environment: environment_id(@environment)}
      opts[:tag] = @tag if @tag.present?
      result = apis[:projects].projects_parameters_list(proj_id, **opts)
      logger.debug do
        cleaned = result&.to_hash&.deep_dup
        cleaned&.[](:results)&.each do |param|
          if param[:secret]
            param[:values].each do |k, v|
              v[:value] = "<masked>" unless v.nil?
            end
            param[:values_flat].each do |v|
              v[:value] = "<masked>" unless v.nil?
            end
          end
        end
        "Parameters query result: #{cleaned.inspect}"
      end
      result&.results&.collect do |param|
        # values is keyed by url, but we forced it to only have a single entry
        # for the supplied environment
        # preserve types so we can generate accurate structured data vs using typify filter
        value = param.values.values.first&.value
        if ! value.nil?
          case param.type
            when "boolean"
              value = (value == "true")
            when "integer"
              value = value.to_i
            else
              value = value.to_s
          end
        end
        Kubetruth::Parameter.new(key: param.name, value: value, secret: param.secret)
      end
    end

    def templates(project:)
      @templates_mutex.acquire do
        @templates ||= {}
        @templates[project] ||= begin
          proj_id = projects[project]
          opts = {environment: environment_id(@environment)}
          opts[:tag] = @tag if @tag.present?
          result = apis[:projects].projects_templates_list(proj_id, **opts)
          logger.debug { "Templates query result: #{result.inspect}" }
          Hash[result&.results&.collect do |tmpl|
            # values is keyed by url, but we forced it to only have a single entry
            # for the supplied environment
            [tmpl.name, tmpl.id]
          end]
        end
      end
    end

    def template_names(project:)
      templates(project: project).keys
    end

    def template_id(template, project:)
      template_id = templates(project: project)[template]
      raise Kubetruth::Error.new("Unknown template: #{template}") unless template_id
      template_id.to_s
    end

    def template(name, project:)
      proj_id = project_id(project)
      tmpl_id = template_id(name, project: project)
      opts = {environment: environment_id(@environment)}
      opts[:tag] = @tag if @tag.present?
      result = apis[:projects].projects_templates_retrieve(tmpl_id, proj_id, **opts)
      body = result&.body
      logger.debug { result.body = "<masked>" if result.has_secret; "Template Retrieve query result: #{result.inspect}" }
      body
    end

  end
end
