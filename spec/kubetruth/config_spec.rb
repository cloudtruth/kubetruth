require 'rspec'
require 'kubetruth/config'

module Kubetruth
  describe Config do

    let(:config) { described_class.new([]) }

    describe "ProjectSpec" do

      it "has same keys for defaults and struct" do
        expect(described_class::ProjectSpec.new.to_h.keys).to eq(described_class::DEFAULT_SPEC.keys)
      end

      it "converts types" do
        spec = described_class::ProjectSpec.new(
          scope: "root",
          name: "myroot",
          project_selector: "foo",
          context: {"name1" => "template1"},
          resource_templates: {"name1" => "template1"},
          environment: "myenv",
          skip: true
        )
        expect(spec.scope).to be_an_instance_of(String)
        expect(spec.scope).to eq("root")
        expect(spec.name).to eq("myroot")
        expect(spec.project_selector).to be_an_instance_of(Regexp)
        expect(spec.project_selector).to eq(/foo/)
        expect(spec.context).to be_an_instance_of(Template::TemplateHashDrop)
        expect(spec.context.liquid_method_missing("name1")).to eq("template1")
        expect(spec.resource_templates["name1"]).to be_an_instance_of(Template)
        expect(spec.resource_templates["name1"].source).to eq("template1")
        expect(spec.environment).to eq("myenv")
        expect(spec.skip).to equal(true)
      end

      describe "#to_s" do

        it "shows as the hash contents only" do
          spec = described_class::ProjectSpec.new(scope: "root", name: "myroot")
          expect("#{spec.to_s}").to match(/{"scope":"root","name":"myroot"/)
          expect("#{spec}").to match(/{"scope":"root","name":"myroot"/)
        end
  
      end  

    end

    describe "initialization" do

      it "sets mappings" do
        expect(config.instance_variable_get(:@project_mapping_crds)).to eq([])
      end
 
    end

    describe "templates" do

      it "returns all templates when active_templates nil" do
        spec = described_class::ProjectSpec.new(
          resource_templates: {"name1" => "template1"}
        )

        expect(spec.templates).to equal(spec[:resource_templates])
      end

      it "filters by active_templates" do
        spec = described_class::ProjectSpec.new(
          active_templates: %w[name2 name3],
          resource_templates: {"name1" => "template1", "name2" => "template2", "name3" => "template3", "name4" => "template4"}
        )

        expect(spec.templates.keys).to eq(["name2" , "name3"])
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
            skip: true,
            included_projects: ["included_projects"],
            context: {"name1" => "template1"},
            resource_templates: {"name1" => "template1"}
          },
          {
            scope: "override",
            project_selector: "project_overrides:project_selector",
            context: {"name1" => "override_template1"},
            resource_templates: {"name1" => "override_template1"}
          }
        ]
        config = described_class.new(data)
        config.load
        expect(config.instance_variable_get(:@config)).to_not eq(Kubetruth::Config::DEFAULT_SPEC)
        expect(config.root_spec).to be_an_instance_of(Kubetruth::Config::ProjectSpec)
        expect(config.root_spec.context).to be_an_instance_of(Kubetruth::Template::TemplateHashDrop)
        expect(config.root_spec.context.liquid_method_missing("name1")).to eq("template1")
        expect(config.root_spec.resource_templates["name1"]).to be_an_instance_of(Kubetruth::Template)
        expect(config.root_spec.resource_templates["name1"].source).to eq("template1")
        expect(config.root_spec.key_selector).to eq(/key_selector/)
        expect(config.override_specs.size).to eq(1)
        expect(config.override_specs.first).to be_an_instance_of(Kubetruth::Config::ProjectSpec)
        expect(config.override_specs.first.context).to be_an_instance_of(Kubetruth::Template::TemplateHashDrop)
        expect(config.override_specs.first.context.liquid_method_missing("name1")).to eq("override_template1")
        expect(config.override_specs.first.resource_templates["name1"]).to be_an_instance_of(Kubetruth::Template)
        expect(config.override_specs.first.resource_templates["name1"].source).to eq("override_template1")
      end

      it "does deep merges on hash types" do
        data = [
          {
            scope: "root",
            context: {"name1" => "template1", "name2" => "template2"},
            resource_templates: {"name1" => "template1", "name2" => "template2"}
          },
          {
            scope: "override",
            context: {"name1" => "override_template1", "name3" => "override_template3"},
            resource_templates: {"name1" => "override_template1", "name3" => "override_template3"}
          }
        ]
        config = described_class.new(data)
        config.load

        expect(config.root_spec.context.liquid_method_missing("name1")).to eq("template1")
        expect(config.root_spec.context.liquid_method_missing("name2")).to eq("template2")
        expect(config.root_spec.context.liquid_method_missing("name3")).to be_nil
        expect(config.root_spec.resource_templates["name1"].source).to eq("template1")
        expect(config.root_spec.resource_templates["name2"].source).to eq("template2")
        expect(config.root_spec.resource_templates["name3"]).to be_nil

        expect(config.override_specs.first.context.liquid_method_missing("name1")).to eq("override_template1")
        expect(config.override_specs.first.context.liquid_method_missing("name2")).to eq("template2")
        expect(config.override_specs.first.context.liquid_method_missing("name3")).to eq("override_template3")
        expect(config.override_specs.first.resource_templates["name1"].source).to eq("override_template1")
        expect(config.override_specs.first.resource_templates["name2"].source).to eq("template2")
        expect(config.override_specs.first.resource_templates["name3"].source).to eq("override_template3")
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
        config = described_class.new([{scope: "override", project_selector: "fo+", resource_templates: {"name1" => "template1"}}])
        spec = config.spec_for_project("foo")
        expect(spec).to_not equal(config.root_spec)
        expect(spec.resource_templates["name1"]).to be_an_instance_of(Kubetruth::Template)
        expect(spec.resource_templates["name1"].source).to eq("template1")
      end

      it "raises for multiple matching specs" do
        config = described_class.new([
          {scope: "override", project_selector: "bo+", resource_templates: ["not"]},
          {scope: "override", project_selector: "fo+", resource_templates: ["first"]},
          {scope: "override", project_selector: "foo", resource_templates: ["second"]}
        ])
        expect { config.spec_for_project("foo") }.to raise_error(Config::DuplicateSelection, /Multiple configuration specs/)
      end

      it "memoizes specs by project name" do
        config = described_class.new([{scope: "override", project_selector: "fo+", resource_templates: ["foocm"]}])
        expect(config.instance_variable_get(:@spec_mapping)).to eq({})
        spec = config.spec_for_project("foo")
        expect(config.instance_variable_get(:@spec_mapping)).to eq({"foo" => spec})
        expect(config.override_specs).to_not receive(:find_all)
        spec2 = config.spec_for_project("foo")
        expect(spec2).to equal(spec)
      end

    end

  end
end
