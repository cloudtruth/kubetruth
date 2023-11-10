require_relative 'project'

module Kubetruth
  class ProjectCollection

    include GemLogger::LoggerSupport

    attr_accessor :projects

    def initialize(project_spec)
      @projects = {}
      @project_spec = project_spec
    end

    def ctapi
      @ctapi ||= Kubetruth::CtApi.new(environment: @project_spec.environment, tag: @project_spec.tag)
    end

    def names
      ctapi.project_names
    end

    def create_project(*args, **kwargs)
      project = Project.new(*args, **kwargs.merge(collection: self, ctapi: ctapi))
      projects[project.name] = project
      project
    end

  end
end
