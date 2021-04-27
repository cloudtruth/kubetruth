require 'rspec'
require 'kubetruth/config'

module Kubetruth
  describe Config do

    let(:config) { described_class.new(config_file: "kubetruth.yaml") }

    describe "initialization" do

      it "sets config file" do
        expect(config.instance_variable_get(:@config_file)).to eq("kubetruth.yaml")
      end

    end

    describe "stale?" do

      it "reports when not up to date" do
        within_construct do |c|
          c.file('kubetruth.yaml', "")
          expect(config.stale?).to be_truthy
          config.load
          expect(config.stale?).to be_falsey
          sleep(0.2) # fails on GithubActions without this
          c.file('kubetruth.yaml', "---")
          expect(config.stale?).to be_truthy
        end
      end

    end

    describe "load" do

      it "set defaults" do
        within_construct do |c|
          c.file('kubetruth.yaml', "")
          expect(config.instance_variable_get(:@config)).to be_nil
          config.load
          expect(config.instance_variable_get(:@config)).to eq(Kubetruth::Config::DEFAULT_SPEC)
        end
      end

      it "is memoized" do
        within_construct do |c|
          c.file('kubetruth.yaml', "")
          expect(config.instance_variable_get(:@config)).to be_nil
          config.load
          old = config.instance_variable_get(:@config)
          expect(File).to receive(:read).never
          config.load
          expect(config.instance_variable_get(:@config)).to equal(old)
        end
      end

      it "raises error for invalid config" do
        within_construct do |c|
          c.file('kubetruth.yaml', YAML.dump(foo: "bar"))
          expect { config.load }.to raise_error(ArgumentError, /unknown keywords: foo/)
          c.file('kubetruth.yaml', YAML.dump(project_overrides: [{bar: "baz"}]))
          expect { config.load }.to raise_error(ArgumentError, /unknown keywords: bar/)
        end
      end

      it "loads data into config" do
        within_construct do |c|
          data = {
            project_selector: "project_selector",
            key_selector: "key_selector",
            key_filter: "key_filter",
            configmap_name_template: "configmap_name_template",
            secret_name_template: "secret_name_template",
            namespace_template: "namespace_template",
            key_template: "key_template",
            skip: true,
            skip_secrets: true,
            included_projects: ["included_projects"],
            project_overrides: [
              {
                project_selector: "project_overrides:project_selector",
                configmap_name_template: "project_overrides:configmap_name_template"
              }
            ]
          }
          c.file('kubetruth.yaml', YAML.dump(data))
          config.load
          expect(config.instance_variable_get(:@config)).to_not eq(Kubetruth::Config::DEFAULT_SPEC)
          data.each do |k, v|
            next if k == :project_overrides
            expect(config.instance_variable_get(:@config)[k]).to eq(data[k])
          end
          expect(config.root_spec).to be_an_instance_of(Kubetruth::Config::ProjectSpec)
          expect(config.root_spec.configmap_name_template).to eq("configmap_name_template")
          expect(config.root_spec.key_selector).to eq(/key_selector/)
          expect(config.override_specs.size).to eq(1)
          expect(config.override_specs.first).to be_an_instance_of(Kubetruth::Config::ProjectSpec)
          expect(config.override_specs.first.configmap_name_template).to eq("project_overrides:configmap_name_template")
          expect(config.override_specs.first.secret_name_template).to eq(config.root_spec.secret_name_template)
        end
      end

    end

    describe "root_spec" do

      it "loads and returns the root spec" do
        within_construct do |c|
          c.file('kubetruth.yaml', "")
          expect(config).to receive(:load).and_call_original
          expect(config.root_spec).to be_an_instance_of(Kubetruth::Config::ProjectSpec)
        end
      end

    end

    describe "override_specs" do

      it "loads and returns the override specs" do
        within_construct do |c|
          c.file('kubetruth.yaml', YAML.dump(project_overrides: [{project_selector: ""}]))
          expect(config).to receive(:load).and_call_original
          expect(config.override_specs).to all(be_an_instance_of(Kubetruth::Config::ProjectSpec))
        end
      end

      it "doesn't return nil when none" do
        within_construct do |c|
          c.file('kubetruth.yaml', "")
          expect(config).to receive(:load).and_call_original
          expect(config.override_specs).to eq([])
        end
      end

    end

    describe "spec_for_project" do

      it "returns root spec if no matching override" do
        within_construct do |c|
          c.file('kubetruth.yaml', "")
          expect(config.spec_for_project("foo")).to equal(config.root_spec)
        end
      end

      it "returns the matching override specs" do
        within_construct do |c|
          c.file('kubetruth.yaml', YAML.dump(project_overrides: [{project_selector: "fo+", configmap_name_template: "foocm"}]))
          spec = config.spec_for_project("foo")
          expect(spec).to_not equal(config.root_spec)
          expect(spec.configmap_name_template).to eq("foocm")
        end
      end

      it "warns for multiple matching specs" do
        within_construct do |c|
          c.file('kubetruth.yaml', YAML.dump(project_overrides: [
            {project_selector: "bo+", configmap_name_template: "not"},
            {project_selector: "fo+", configmap_name_template: "first"},
            {project_selector: "foo", configmap_name_template: "second"}
          ]))
          spec = config.spec_for_project("foo")
          expect(Logging.contents).to include("Multiple configuration specs match the project")
          expect(spec.configmap_name_template).to eq("first")
        end
      end

    end

  end
end
