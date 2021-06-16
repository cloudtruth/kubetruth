module Kubetruth
  Project = Struct.new(:name, :spec, keyword_init: true) do

    include GemLogger::LoggerSupport

    cattr_accessor :ctapi_context

    def self.ctapi
      @ctapi ||= begin
        ctx = ctapi_context.dup
        @ctapi_class = Kubetruth::CtApi(api_key: ctx.delete(:api_key), api_url: ctx.delete(:api_url))
        @ctapi_class.new(**ctx)
      end
    end

    def ctapi
      self.class.ctapi
    end

    def self.names
      ctapi.project_names
    end

    def self.reset
      @all = nil
    end

    def self.all
      @all ||= {}
    end

    def self.create(*args, **kwargs)
      project = new(*args, **kwargs)
      all[project.name] = project
    end

    def parameters
      @parameters ||= begin
        result = []

        # First search for all the selected parameters
        #
        searchTerm = ""
        if spec.key_selector.source =~ /^[\w\.\-]*$/
          logger.debug {"Simple key_selector '#{spec.key_selector.source}', using as search filter to fetch parameters"}
          searchTerm = spec.key_selector.source
        else
          logger.debug {"Complex key_selector '#{spec.key_selector.source}', using as client-side regexp match against parameters"}
        end

        params = ctapi.parameters(searchTerm: searchTerm, project: name)
        logger.debug do
          cleaned = params.deep_dup
          cleaned.each {|p| p.value = "<masked>" if p.secret}
          "Params fetched from cloudtruth: #{cleaned.inspect}"
        end

        if searchTerm.blank? && spec.key_selector.source.present?
          logger.debug {"Looking for key pattern matches to '#{spec.key_selector.inspect}'"}
          params = params.select do |param|
            if param.key.match(spec.key_selector)
              logger.debug {"Pattern matches '#{param.key}'"}
              true
            else
              logger.debug {"Pattern does not match '#{param.key}'"}
              false
            end
          end
        end

        logger.debug { "Parameters selected for #{name}: #{params.collect {|p| p.key }.inspect}" }

        params
      end
    end

    # Yields each project to the optional block in a DFS fashion
    def included_projects(seen: [], &block)
      result = {}
      seen = seen + [name]

      spec.included_projects.each do |included_project_name|
        if seen.include?(included_project_name)
          logger.info "Breaking circular dependency in included project: #{(seen + [included_project_name]).join(' -> ')}"
          next
        end

        project = self.class.all[included_project_name]
        if project.nil?
          # should never get here as ETL preloads all referenced projects
          logger.warn "Skipping unknown project '#{included_project_name}' included by project '#{name}'"
          next
        end

        result[project.name] = project.included_projects(seen: seen, &block)
        yield project if block
      end

      result
    end

    def all_parameters
      params = []
      included_projects do |project|
        params.concat(project.parameters)
      end
      params.concat(parameters)
      params
    end

    def parameter_origins
      origins = {}

      included_projects do |project|
        project.parameters.each do |p|
          origins[p.key] ||= []
          origins[p.key] << project.name
        end
      end

      parameters.each do |p|
        origins[p.key] ||= []
        origins[p.key] << name
      end

      origins.merge!(origins) do |_, v|
        origin = "#{v.pop}"
        if v.length > 0
          origin << " (#{v.reverse.join(" -> ")})"
        end
        origin
      end

      origins
    end

    def heirarchy
      {self.name => included_projects}
    end

  end
end
