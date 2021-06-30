require "graphql/client"
require "graphql/client/http"
require_relative 'parameter'

module Kubetruth

  def self.ctapi_setup(api_key:, api_url: nil)
    unless Kubetruth.const_defined?(:CtApi)
      api_url ||= "https://api.cloudtruth.com/graphql"

      clazz = Class.new do

        include GemLogger::LoggerSupport

        cattr_accessor :http, :schema, :client, :queries

        self.http = ::GraphQL::Client::HTTP.new(api_url) do
          define_method :headers do |context = {}|
            { "User-Agent": "kubetruth/#{Kubetruth::VERSION}", "Authorization": "Bearer #{api_key}" }
          end
        end
        self.schema = ::GraphQL::Client.load_schema(http)
        self.client = ::GraphQL::Client.new(schema: schema, execute: http)
        self.client.allow_dynamic_queries = true

        self.queries = {}

        self.queries[:EnvironmentsQuery] = client.parse <<~GRAPHQL
          query {
            viewer {
              organization {
                environments {
                  nodes {
                    id
                    name
                  }
                }
              }
            }
          }
        GRAPHQL

        self.queries[:ProjectsQuery] = client.parse <<~GRAPHQL
          query {
            viewer {
              organization {
                projects {
                  nodes {
                    id
                    name
                  }
                }
              }
            }
          }
        GRAPHQL

        self.queries[:ParametersQuery] = client.parse <<~GRAPHQL
          query($environmentId: ID, $projectName: String, $searchTerm: String) {
            viewer {
              organization {
                project(name: $projectName) {
                  parameters(searchTerm: $searchTerm, orderBy: { keyName: ASC }) {
                    nodes {
                      id
                      keyName
                      isSecret
                      environmentValue(environmentId: $environmentId) {
                        parameterValue
                      }
                    }
                  }
                }
              }
            }
          }
        GRAPHQL

        def initialize()
        end

        def environments
          @environments ||= begin
                              variables = {}
                              result = client.query(self.queries[:EnvironmentsQuery], variables: variables)
                              logger.debug{"Environments query result: #{result.inspect}"}
                              Hash[result&.data&.viewer&.organization&.environments&.nodes&.collect {|e| [e.name, e.id] }]
                            end
        end

        def environment_id(environment)
          env_id = self.environments[environment]

          # retry in case environments have been updated upstream since we cached
          # them
          if env_id.nil? && ! @environments.nil?
            logger.debug {"Unknown environment, retrying after clearing cache"}
            @environments = nil
            env_id = self.environments[environment]
          end

          raise("Unknown environment: #{environment}") unless env_id
          env_id.to_s
        end

        def projects
          variables = {}
          result = client.query(self.queries[:ProjectsQuery], variables: variables)
          logger.debug{"Projects query result: #{result.inspect}"}
          Hash[result&.data&.viewer&.organization&.projects&.nodes&.collect {|e| [e.name, e.id] }]
        end

        def environment_names
          environments.keys
        end

        def project_names
          projects.keys
        end

        def parameters(searchTerm: "", project: nil, environment: "default")
          variables = {searchTerm: searchTerm, environmentId: environment_id(environment)}
          variables[:projectName] = project if project.present?

          result = client.query(self.queries[:ParametersQuery], variables: variables)
          logger.debug do
            cleaned = result&.original_hash&.deep_dup
            cleaned&.[]("data")&.[]("viewer")&.[]("organization")&.[]("project")&.[]("parameters")&.[]("nodes")&.each do |e|
              e["environmentValue"]["parameterValue"] = "<masked>" if e["isSecret"]
            end
            "Parameters query result: #{cleaned.inspect}, errors: #{result&.errors.inspect}"
          end

          result&.data&.viewer&.organization&.project&.parameters&.nodes&.collect do |e|
            Kubetruth::Parameter.new(key: e.key_name, value: e.environment_value.parameter_value, secret: e.is_secret)
          end
        end

      end

      Kubetruth.const_set(:CtApi, clazz)
    end
    ::Kubetruth::CtApi
  end

end
