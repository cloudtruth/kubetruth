require_relative 'project'

module Kubetruth
  class ProjectCollection

    include GemLogger::LoggerSupport

    attr_accessor :projects

    def initialize(config)
      @projects = {}
      @config = config
    end

    def names
      # NOTE: listing projects is done using env/tag from root spec, and not the
      # env/tag from project specific overrides.  This could cause an issue if
      # the tag on the root spec differs from the tag on the project spec in
      # such a way that the listing of projects gets (doesn't) one that is not
      # (is) visible to the project tag, but makes for a better UX by allowing
      # an override spec to override env/tag in root spec
      # the ctapi create factory method caches based on env/tag
      Kubetruth::CtApi.create(environment: @config.root_spec.environment, tag: @config.root_spec.tag).project_names
    end

    def create_project(*args, **kwargs)
      # the ctapi create factory method caches based on env/tag
      spec = kwargs[:spec]
      ctapi = Kubetruth::CtApi.create(environment: spec.environment, tag: spec.tag)
      project = Project.new(*args, **kwargs.merge(collection: self, ctapi: ctapi))
      projects[project.name] = project
      project
    end

  end
end
