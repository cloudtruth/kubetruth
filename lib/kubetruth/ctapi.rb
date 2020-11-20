require_relative 'logging'
require "graphql/client"
require "graphql/client/http"

module Kubetruth
  class CtApi

    include GemLogger::LoggerSupport

    GRAPH_ENDPOINT = ENV["CT_API_URL"] || "https://api.cloudtruth.com/graphql"

    HTTP = ::GraphQL::Client::HTTP.new(GRAPH_ENDPOINT) do
      def headers(context = {})
        { "Authorization": "Bearer #{ENV["CT_API_KEY"]}" }
      end
    end

    Schema = ::GraphQL::Client.load_schema(HTTP)
    #Schema = ::GraphQL::Client.from_definition("graphql/schema.graphql")

    Client = ::GraphQL::Client.new(schema: Schema, execute: HTTP)

    EnvironmentsQuery = Client.parse <<~GRAPHQL
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

    ParametersQuery = Client.parse <<~GRAPHQL
      query($environmentId: ID, $searchTerm: String) {
        viewer {
          organization {
            parameters(searchTerm: $searchTerm, orderBy: { keyName: ASC }) {
              nodes {
                id
                keyName
                environmentValue(environmentId: $environmentId) {
                  parameterValue
                }
              }
            }
          }
        }
      }
    GRAPHQL

    def initialize(environment="default")
      @environment = environment
    end

    def environments
      result = Client.query(EnvironmentsQuery)
      logger.debug{"Environments query result: #{result.inspect}"}
      Hash[result&.data&.viewer&.organization&.environments&.nodes&.collect {|e| [e.name, e.id] }]
    end

    def environment_names
      environments.keys
    end

    def parameters(searchTerm: "")
      env_id = self.environments[@environment]
      result = Client.query(ParametersQuery, variables: { searchTerm: searchTerm, environmentId: env_id.to_s })
      logger.debug{"Parameters query result: #{result.inspect}"}
      Hash[result&.data&.viewer&.organization&.parameters&.nodes&.collect {|e| [e.key_name, e.environment_value.parameter_value] }]
    end

  end
end
