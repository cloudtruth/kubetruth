require_relative 'template'

module Kubetruth
  class Config

    include GemLogger::LoggerSupport

    class DuplicateSelection < Kubetruth::Error; end

    ProjectSpec = Struct.new(
      :scope,
      :project_selector,
      :key_selector,
      :skip,
      :skip_secrets,
      :included_projects,
      :configmap_template,
      :secret_template,
      keyword_init: true
    ) do

      def initialize(*args, **kwargs)
        super(*args, **convert_types(kwargs))
      end

      def convert_types(hash)
        selector_key_pattern = /_selector$/
        template_key_pattern = /_template$/
        hash.merge(hash) do |k, v|
          case k
            when selector_key_pattern
              Regexp.new(v)
            when template_key_pattern
              Kubetruth::Template.new(v)
            else
              v
          end
        end
      end

    end

    DEFAULT_SPEC = {
      scope: 'override',
      project_selector: '',
      key_selector: '',
      skip: false,
      skip_secrets: false,
      included_projects: [],
      configmap_template: "",
      secret_template: ""
    }.freeze

    def initialize(project_mapping_crds)
      @project_mapping_crds = project_mapping_crds
      @spec_mapping = {}
    end

    def load
      @config ||= begin
        parts = @project_mapping_crds.group_by {|c| c[:scope] }
        raise ArgumentError.new("Multiple root ProjectMappings") if parts["root"] && parts["root"].size > 1

        root_mapping = parts["root"]&.first || {}
        overrides = parts["override"] || []

        config = DEFAULT_SPEC.merge(root_mapping)
        @root_spec = ProjectSpec.new(**config)
        @override_specs = overrides.collect { |o| ProjectSpec.new(**config.merge(o)) }
        config
      end
    end

    def root_spec
      load
      @root_spec
    end

    def override_specs
      load
      @override_specs
    end

    def spec_for_project(project_name)
      spec = @spec_mapping[project_name]
      return spec unless spec.nil?

      specs = override_specs.find_all { |o| project_name =~ o.project_selector }
      case specs.size
        when 0
          spec = root_spec
          logger.debug {"Using root spec for project '#{project_name}'"}
        when 1
          spec = specs.first
          logger.debug {"Using override spec '#{spec.project_selector}' for project '#{project_name}'"}
        else
          dupes = specs.collect {|s| "'#{s.project_selector}'" }
          raise DuplicateSelection, "Multiple configuration specs (#{dupes.inspect}) match the project '#{project_name}': }"
      end

      @spec_mapping[project_name] = spec
      return spec
    end

  end
end
