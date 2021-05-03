require 'rspec'
require 'kubetruth/config'

module Kubetruth
  describe Config do

    let(:config) { described_class.new([]) }

    describe "initialization" do

      it "sets mappings" do
        expect(config.instance_variable_get(:@project_mapping_crds)).to eq([])
      end

      it "has same keys for defaults and struct" do
        expect(described_class::ProjectSpec.new.to_h.keys).to eq(described_class::DEFAULT_SPEC.keys)
      end

    end

    describe "load" do

      it "set defaults" do
        expect(config.instance_variable_get(:@config)).to be_nil
        config.load
        expect(config.instance_variable_get(:@config)).to eq(Kubetruth::Config::DEFAULT_SPEC)
      end

      it "is memoized" do
        expect(config.instance_variable_get(:@config)).to be_nil
        config.load
        old = config.instance_variable_get(:@config)
        expect(Kubetruth::Config::ProjectSpec).to receive(:new).never
        config.load
        expect(config.instance_variable_get(:@config)).to equal(old)
      end

      it "raises error for invalid config" do
        config = described_class.new([{scope: "root", foo: "bar"}])
        expect { config.load }.to raise_error(ArgumentError, /unknown keywords: foo/)
        config = described_class.new([{scope: "override", bar: "baz"}])
        expect { config.load }.to raise_error(ArgumentError, /unknown keywords: bar/)
      end

      it "raises error for multiple root scopes" do
        config = described_class.new([{scope: "root", foo: "bar"}, {scope: "root", bar: "baz"}])
        expect { config.load }.to raise_error(ArgumentError, /Multiple root/)
      end

      it "loads data into config" do
        data = [
          {
            scope: "root",
            project_selector: "project_selector",
            key_selector: "key_selector",
            key_filter: "key_filter",
            configmap_name_template: "configmap_name_template",
            secret_name_template: "secret_name_template",
            namespace_template: "namespace_template",
            key_template: "key_template",
            skip: true,
            skip_secrets: true,
            included_projects: ["included_projects"]
          },
          {
            scope: "override",
            project_selector: "project_overrides:project_selector",
            configmap_name_template: "project_overrides:configmap_name_template"
          }
        ]
        config = described_class.new(data)
        config.load
        expect(config.instance_variable_get(:@config)).to_not eq(Kubetruth::Config::DEFAULT_SPEC)
        expect(config.root_spec).to be_an_instance_of(Kubetruth::Config::ProjectSpec)
        expect(config.root_spec.configmap_name_template).to be_an_instance_of(Kubetruth::Template)
        expect(config.root_spec.configmap_name_template.source).to eq("configmap_name_template")
        expect(config.root_spec.key_selector).to eq(/key_selector/)
        expect(config.override_specs.size).to eq(1)
        expect(config.override_specs.first).to be_an_instance_of(Kubetruth::Config::ProjectSpec)
        expect(config.override_specs.first.configmap_name_template).to be_an_instance_of(Kubetruth::Template)
        expect(config.override_specs.first.configmap_name_template.source).to eq("project_overrides:configmap_name_template")
        expect(config.override_specs.first.secret_name_template.source).to eq(config.root_spec.secret_name_template.source)
      end

    end

    describe "root_spec" do

      it "loads and returns the root spec" do
        expect(config).to receive(:load).and_call_original
        expect(config.root_spec).to be_an_instance_of(Kubetruth::Config::ProjectSpec)
      end

    end

    describe "override_specs" do

      it "loads and returns the override specs" do
        config = described_class.new([{scope: "override", project_selector: ""}])
        expect(config).to receive(:load).and_call_original
        expect(config.override_specs).to all(be_an_instance_of(Kubetruth::Config::ProjectSpec))
      end

      it "doesn't return nil when none" do
        expect(config).to receive(:load).and_call_original
        expect(config.override_specs).to eq([])
      end

    end

    describe "spec_for_project" do

      it "returns root spec if no matching override" do
        expect(config.spec_for_project("foo")).to equal(config.root_spec)
      end

      it "returns the matching override specs" do
        config = described_class.new([{scope: "override", project_selector: "fo+", configmap_name_template: "foocm"}])
        spec = config.spec_for_project("foo")
        expect(spec).to_not equal(config.root_spec)
        expect(spec.configmap_name_template).to be_an_instance_of(Kubetruth::Template)
        expect(spec.configmap_name_template.source).to eq("foocm")
      end

      it "warns for multiple matching specs" do
        config = described_class.new([
          {scope: "override", project_selector: "bo+", configmap_name_template: "not"},
          {scope: "override", project_selector: "fo+", configmap_name_template: "first"},
          {scope: "override", project_selector: "foo", configmap_name_template: "second"}
        ])
        spec = config.spec_for_project("foo")
        expect(Logging.contents).to include("Multiple configuration specs match the project")
        expect(spec.configmap_name_template).to be_an_instance_of(Kubetruth::Template)
        expect(spec.configmap_name_template.source).to eq("first")
      end

    end

  end
end
