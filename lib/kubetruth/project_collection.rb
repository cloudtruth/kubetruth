require_relative 'project'

module Kubetruth
  class ProjectCollection

    include GemLogger::LoggerSupport

    attr_accessor :projects

    def initialize()
      @projects = {}
    end

    def ctapi
      @ctapi ||= begin
        Kubetruth::CtApi.new
      end
    end

    def names
      ctapi.project_names
    end

    def create_project(*args, **kwargs)
      project = Project.new(*args, **kwargs, collection: self)
      projects[project.name] = project
      project
    end

  end
end
