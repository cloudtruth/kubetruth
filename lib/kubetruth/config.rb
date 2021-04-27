require_relative 'logging'

module Kubetruth
  class Config

    include GemLogger::LoggerSupport

    ProjectSpec = Struct.new(
      :project_selector,
      :key_selector,
      :key_filter,
      :configmap_name_template,
      :secret_name_template,
      :namespace_template,
      :key_template,
      :skip,
      :skip_secrets,
      :included_projects,
      keyword_init: true
    )

    DEFAULT_SPEC = {
      project_selector: '',
      key_selector: '',
      key_filter: '',
      configmap_name_template: '%{project}',
      secret_name_template: '%{project}',
      namespace_template: '',
      key_template: '%{key}',
      skip: false,
      skip_secrets: false,
      included_projects: []
    }.freeze

    def initialize(config_file:)
      @config_file = config_file
    end

    def convert_types(hash)
      selector_key_pattern = /_selector$/
      hash.merge(hash) do |k, v|
        k =~ selector_key_pattern ? Regexp.new(v) : v
      end
    end

    def stale?
      @last_read != File.mtime(@config_file)
    end

    def load
      @config ||= begin
        begin
          config = YAML.load(File.read(@config_file)) || {}
          @last_read = File.mtime(@config_file)
        rescue => e
          logger.warn("Unable to load config file: #{@config_file}, using defaults")
          config = {}
        end
        overrides = config.delete(:project_overrides) || {}
        config = DEFAULT_SPEC.merge(config)
        @root_spec = ProjectSpec.new(**convert_types(config))
        @override_specs = overrides.collect { |o| ProjectSpec.new(convert_types(config.merge(o))) }
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
      spec = nil
      specs = override_specs.find_all { |o| project_name =~ o.project_selector }
      case specs.size
        when 0
          spec = root_spec
        when 1
          spec = specs.first
        else
          logger.warn "Multiple configuration specs match the project '#{project_name}', using first: #{specs.collect(&:project_selector).inspect}"
          spec = specs.first
      end
      spec
    end

  end
end
