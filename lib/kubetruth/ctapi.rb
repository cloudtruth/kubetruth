require_relative 'logging'
require_relative 'parameter'
require "graphql/client"
require "graphql/client/http"

module Kubetruth

  def self.CtApi(api_key:, api_url: nil)
    api_url ||= "https://api.cloudtruth.com/graphql"

    Class.new do

      include GemLogger::LoggerSupport

      cattr_accessor :http, :schema, :client, :queries
      attr_accessor :environment, :organization

      self.http = ::GraphQL::Client::HTTP.new(api_url) do
        define_method :headers do |context = {}|
          { "User-Agent": "kubetruth/#{Kubetruth::VERSION}", "Authorization": "Bearer #{api_key}" }
        end
      end
      self.schema = ::GraphQL::Client.load_schema(http)
      self.client = ::GraphQL::Client.new(schema: schema, execute: http)
      self.client.allow_dynamic_queries = true

      self.queries = {}
      self.queries[:OrganizationsQuery] = client.parse <<~GRAPHQL
        query {
          viewer {
            memberships {
              nodes {
                organization {
                  id
                  name
                }
              }
            }
          }
        }
      GRAPHQL

      self.queries[:EnvironmentsQuery] = client.parse <<~GRAPHQL
        query($organizationId: ID) {
          viewer {
            organization(id: $organizationId) {
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
        query($organizationId: ID) {
          viewer {
            organization(id: $organizationId) {
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
        query($organizationId: ID, $environmentId: ID, $projectName: String, $searchTerm: String) {
          viewer {
            organization(id: $organizationId) {
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

      def initialize(environment: "default", organization: nil)
        @environment = environment
        @organization = organization
      end

      def organizations
        @organizations ||= begin
                             result = client.query(self.queries[:OrganizationsQuery])
                             logger.debug{"Organizations query result: #{result.inspect}"}
                             Hash[result&.data&.viewer&.memberships&.nodes&.collect {|o| [o.organization.name, o.organization.id] }]
                           end
      end

      def environments
        @environments ||= begin
                            variables = {}
                            if @organization
                              org_id = self.organizations[@organization] || raise("Unknown organization: #{@organization}")
                              variables[:organizationId] = org_id
                            end

                            result = client.query(self.queries[:EnvironmentsQuery], variables: variables)
                            logger.debug{"Environments query result: #{result.inspect}"}
                            Hash[result&.data&.viewer&.organization&.environments&.nodes&.collect {|e| [e.name, e.id] }]
                          end
      end

      def projects
        @projects ||= begin
          variables = {}
          if @organization
            org_id = self.organizations[@organization] || raise("Unknown organization: #{@organization}")
            variables[:organizationId] = org_id
          end

          result = client.query(self.queries[:ProjectsQuery], variables: variables)
          logger.debug{"Projects query result: #{result.inspect}"}
          Hash[result&.data&.viewer&.organization&.projects&.nodes&.collect {|e| [e.name, e.id] }]
        end
      end

      def organization_names
        organizations.keys
      end

      def environment_names
        environments.keys
      end

      def project_names
        projects.keys
      end

      def parameters(searchTerm: "", project: nil)
        env_id = self.environments[@environment] || raise("Unknown environment: #{@environment}")
        variables = {searchTerm: searchTerm, environmentId: env_id.to_s}

        if @organization
          org_id = self.organizations[@organization] || raise("Unknown organization: #{@organization}")
          variables[:organizationId] = org_id
        end

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
  end

end
