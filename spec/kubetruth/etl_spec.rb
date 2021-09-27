require 'rspec'
require 'kubetruth/etl'
require 'kubetruth/project_collection'
require 'kubetruth/parameter'

module Kubetruth
  describe ETL do

    let(:etl) { described_class.new }

    before(:each) do
      @kubeapi = double(Kubetruth::KubeApi)
      allow(@kubeapi).to receive(:get_resource).and_return(Kubeclient::Resource.new)
      allow(@kubeapi).to receive(:apply_resource)
      allow(@kubeapi).to receive(:under_management?).and_return(true)
      allow(@kubeapi).to receive(:set_managed)
      allow(@kubeapi).to receive(:ensure_namespace)
      allow(@kubeapi).to receive(:namespace).and_return("default")
      allow(@kubeapi).to receive(:get_project_mappings).and_return([])
      allow_any_instance_of(described_class).to receive(:kubeapi).and_return(@kubeapi)
    end

    describe "#interruptible_sleep" do

      it "runs for interval without interruption" do
        t = Time.now.to_f
        etl.interruptible_sleep(0.2)
        expect(Time.now.to_f - t).to be >= 0.2
      end

      it "can be interrupted" do
        Thread.new do
          sleep 0.1
          etl.interrupt_sleep
        end
        t = Time.now.to_f
        etl.interruptible_sleep(0.5)
        expect(Time.now.to_f - t).to be < 0.2
      end

    end

    describe "#with_polling" do

      class ForceExit < Exception; end

      it "runs with an interval" do
        watcher = double()
        expect(@kubeapi).to receive(:watch_project_mappings).and_return(watcher).twice
        expect(watcher).to receive(:each).twice
        expect(watcher).to receive(:finish).twice
        expect(etl).to receive(:apply).twice

        count = 0
        expect(etl).to receive(:interruptible_sleep).
          with(0.2).twice { |m, *args| count += 1; raise ForceExit if count > 1 }

        begin
          etl.with_polling(0.2) do
            etl.apply
          end
        rescue ForceExit
        end
        expect(count).to eq(2)

      end

      it "isolates run loop from block failures" do
        watcher = double()
        expect(@kubeapi).to receive(:watch_project_mappings).and_return(watcher).twice
        expect(watcher).to receive(:each).twice
        expect(watcher).to receive(:finish).twice
        expect(etl).to receive(:apply).and_raise("fail").twice

        count = 0
        expect(etl).to receive(:interruptible_sleep).
          with(0.2).twice { |m, *args| count += 1; raise ForceExit if count > 1 }

        begin
          etl.with_polling(0.2) do
            etl.apply
          end
        rescue ForceExit
        end
        expect(count).to eq(2)

      end

      it "treats Kubetruth::Error differently in block failures" do
        watcher = double()
        expect(@kubeapi).to receive(:watch_project_mappings).and_return(watcher).twice
        expect(watcher).to receive(:each).twice
        expect(watcher).to receive(:finish).twice
        expect(etl).to receive(:apply) do
          Kubetruth::Template.new("{{bad}}").render
        end.twice

        count = 0
        expect(etl).to receive(:interruptible_sleep).
          with(0.2).twice { |m, *args| count += 1; raise ForceExit if count > 1 }

        begin
          etl.with_polling(0.2) do
            etl.apply
          end
        rescue ForceExit
        end
        expect(count).to eq(2)
        expect(Logging.contents).to_not match(/Failure while applying config transforms/)
        expect(Logging.contents).to match(/Template failed to render/)
      end

      it "interrupts sleep on watch event" do
        watcher = double()
        notice = double("notice", type: "UPDATED", object: double("kube_resource"))
        expect(@kubeapi).to receive(:watch_project_mappings).and_return(watcher)
        expect(watcher).to receive(:each).and_yield(notice)
        expect(watcher).to receive(:finish)
        expect(etl).to receive(:apply)
        expect(etl).to receive(:interrupt_sleep)

        expect(etl).to receive(:interruptible_sleep).
          with(0.2) { |m, *args| sleep(0.2); raise ForceExit }

        begin
          etl.with_polling(0.2) do
            etl.apply
          end
        rescue ForceExit
        end

      end

      it "skips next sleep when crds get written" do
        watcher = double()
        expect(@kubeapi).to receive(:watch_project_mappings).and_return(watcher)
        allow(watcher).to receive(:each)
        allow(watcher).to receive(:finish)
        expect(etl).to receive(:interruptible_sleep).and_raise(ForceExit)

        count = 0
        begin
          etl.with_polling(0.2) do
            if count == 0
              etl.instance_variable_set(:@wrote_crds, true)
            end
            count += 1
          end
        rescue ForceExit
        end

        expect(etl.instance_variable_get(:@wrote_crds)).to eq(false)
        expect(count).to eq(2)
      end

    end

    describe "#load_config" do

      it "raises if no primary" do
        allow(@kubeapi).to receive(:namespace).and_return("primary-ns")
        expect(@kubeapi).to receive(:get_project_mappings).and_return({})
        expect { etl.load_config }.to raise_error(Kubetruth::Error, /A default set of mappings is required/)
      end

      it "loads config for a single instance" do
        allow(@kubeapi).to receive(:namespace).and_return("primary-ns")
        expect(@kubeapi).to receive(:get_project_mappings).and_return(
          {
            "primary-ns" => {
              "myroot" => Config::DEFAULT_SPEC.merge(scope: "root", name: "myroot"),
              "override1" => Config::DEFAULT_SPEC.merge(scope: "override", name: "override1"),
              "override2" => Config::DEFAULT_SPEC.merge(scope: "override", name: "override2")
            }
          })
        configs = etl.load_config
        expect(configs.size).to eq(1)
        expect(configs.first).to be_an_instance_of(Kubetruth::Config)
        expect(configs.first.root_spec.name).to eq("myroot")
        expect(configs.first.override_specs.collect(&:name)).to eq(["override1","override2"])
      end

      it "loads config for multiple instances" do
        allow(@kubeapi).to receive(:namespace).and_return("primary-ns")
        expect(@kubeapi).to receive(:get_project_mappings).and_return(
          {
            "primary-ns" => {
              "myroot" => Config::DEFAULT_SPEC.merge(scope: "root", name: "myroot"),
              "override1" => Config::DEFAULT_SPEC.merge(scope: "override", name: "override1")
            },
            "other-ns" => {
              "myroot" => Config::DEFAULT_SPEC.merge(scope: "root", name: "myroot", environment: "otherenv"),
              "override1" => Config::DEFAULT_SPEC.merge(scope: "override", name: "override1")
            }
          })
        configs = etl.load_config
        expect(configs.size).to eq(2)
        expect(configs.first).to be_an_instance_of(Kubetruth::Config)
        expect(configs.first.root_spec.name).to eq("myroot")
        expect(configs.first.override_specs.collect(&:name)).to eq(["override1"])
        expect(configs.last).to be_an_instance_of(Kubetruth::Config)
        expect(configs.last.root_spec.name).to eq("myroot")
        expect(configs.last.root_spec.environment).to eq("otherenv")
        expect(configs.last.override_specs.collect(&:name)).to eq(["override1"])
      end

      it "yields config for multiple instances" do
        allow(@kubeapi).to receive(:namespace).and_return("primary-ns")
        expect(@kubeapi).to receive(:get_project_mappings).and_return(
          {
            "primary-ns" => {
              "myroot" => Config::DEFAULT_SPEC.merge(scope: "root", name: "myroot"),
            },
            "other-ns" => {
              "myroot" => Config::DEFAULT_SPEC.merge(scope: "root", name: "myroot", environment: "otherenv"),
            },
            "yetanother-ns" => {
              "myroot" => Config::DEFAULT_SPEC.merge(scope: "root", name: "myroot", environment: "env3"),
            }
          })

        nses = ["primary-ns", "other-ns", "yetanother-ns"]
        envs = ["default", "otherenv",  "env3"]
        etl.load_config do |ns, config|
          expect(ns).to eq(nses.shift)
          expect(config.root_spec.environment).to eq(envs.shift)
        end
      end

    end

    describe "#with_log_level" do

      it "does not set nil log level" do
        expect(Kubetruth::Logging.root_log_level).to eq("debug")
        etl.with_log_level(nil) do
          expect(Kubetruth::Logging.root_log_level).to eq("debug")
        end
        expect(Kubetruth::Logging.root_log_level).to eq("debug")
      end

      it "temporarily sets log level" do
        expect(Kubetruth::Logging.root_log_level).to eq("debug")
        etl.with_log_level("error") do
          expect(Kubetruth::Logging.root_log_level).to eq("error")
        end
        expect(Kubetruth::Logging.root_log_level).to eq("debug")
      end

    end

    describe "#kube_apply" do

      it "calls kube to create new resource" do
        resource_yml = <<~EOF
          apiVersion: v1
          kind: ConfigMap
          metadata:
            name: "group1"
          data:
            "param1": "value1"
        EOF
        parsed_yml = YAML.load(resource_yml)
        expect(@kubeapi).to receive(:ensure_namespace).with(@kubeapi.namespace)
        expect(@kubeapi).to receive(:get_resource).with("configmaps", "group1", namespace: @kubeapi.namespace, apiVersion: "v1").and_raise(Kubeclient::ResourceNotFoundError.new(1, "", 2))
        expect(@kubeapi).to receive(:set_managed)
        expect(@kubeapi).to_not receive(:under_management?)
        expect(@kubeapi).to receive(:apply_resource).with(parsed_yml)
        etl.kube_apply(parsed_yml)
        expect(Logging.contents).to match(/Creating kubernetes resource/)
        expect(etl.instance_variable_get(:@wrote_crds)).to eq(false)
      end

      it "calls to kube to update existing resource" do
        resource_yml = <<~EOF
          apiVersion: v1
          kind: ConfigMap
          metadata:
            name: "group1"
          data:
            "param1": "value1"
        EOF
        parsed_yml = YAML.load(resource_yml)
        resource = Kubeclient::Resource.new(parsed_yml.merge(data: {param1: "oldvalue"}))
        expect(@kubeapi).to receive(:get_resource).with("configmaps", "group1", namespace: @kubeapi.namespace, apiVersion: "v1").and_return(resource)
        expect(@kubeapi).to receive(:set_managed)
        expect(@kubeapi).to receive(:under_management?).and_return(true)
        expect(@kubeapi).to receive(:apply_resource).with(parsed_yml)
        etl.kube_apply(parsed_yml)
        expect(Logging.contents).to match(/Updating kubernetes resource/)
        expect(etl.instance_variable_get(:@wrote_crds)).to eq(false)
      end

      it "skips call to kube for existing resource not under management" do
        resource_yml = <<~EOF
          apiVersion: v1
          kind: ConfigMap
          metadata:
            name: "group1"
          data:
            "param1": "value1"
        EOF
        parsed_yml = YAML.load(resource_yml)
        resource = Kubeclient::Resource.new(parsed_yml)
        expect(@kubeapi).to receive(:get_resource).with("configmaps", "group1", namespace: @kubeapi.namespace, apiVersion: "v1").and_return(resource)
        expect(@kubeapi).to receive(:set_managed)
        expect(@kubeapi).to receive(:under_management?).and_return(false)
        expect(@kubeapi).to_not receive(:apply_resource)
        etl.kube_apply(parsed_yml)
        expect(Logging.contents).to match(/Skipping.*kubetruth management/)
      end

      it "uses namespace for kube when supplied" do
        resource_yml = <<~EOF
          apiVersion: v1
          kind: ConfigMap
          metadata:
            name: "group1"
            namespace: "ns1"
          data:
            "param1": "value1"
        EOF
        parsed_yml = YAML.load(resource_yml)
        expect(@kubeapi).to receive(:ensure_namespace).with("ns1")
        expect(@kubeapi).to receive(:get_resource).with("configmaps", "group1", namespace: "ns1", apiVersion: "v1").and_raise(Kubeclient::ResourceNotFoundError.new(1, "", 2))
        expect(@kubeapi).to receive(:set_managed)
        expect(@kubeapi).to_not receive(:under_management?)
        expect(@kubeapi).to receive(:apply_resource).with(parsed_yml)
        etl.kube_apply(parsed_yml)
        expect(Logging.contents).to match(/Creating kubernetes resource/)
      end

      it "uses apiVersion for kube when supplied" do
        resource_yml = <<~EOF
          apiVersion: kubetruth.cloudtruth.com/v1
          kind: ProjectMapping
          metadata:
            name: "group1"
          spec:
            skip: true
        EOF
        parsed_yml = YAML.load(resource_yml)
        expect(@kubeapi).to receive(:get_resource).with("projectmappings", "group1", namespace: @kubeapi.namespace, apiVersion: "kubetruth.cloudtruth.com/v1").and_raise(Kubeclient::ResourceNotFoundError.new(1, "", 2))
        expect(@kubeapi).to receive(:set_managed)
        expect(@kubeapi).to_not receive(:under_management?)
        expect(@kubeapi).to receive(:apply_resource).with(parsed_yml)
        etl.kube_apply(parsed_yml)
        expect(Logging.contents).to match(/Creating kubernetes resource/)
      end

      it "registers project mapping writes on new resource" do
        resource_yml = <<~EOF
          apiVersion: v1
          kind: ProjectMapping
          metadata:
            name: "pm1"
          spec:
            "scope": "override"
        EOF
        parsed_yml = YAML.load(resource_yml)
        resource = Kubeclient::Resource.new(parsed_yml.merge(metadata: {resourceVersion: "123"}))

        expect(etl.instance_variable_get(:@wrote_crds)).to eq(false)
        expect(@kubeapi).to receive(:get_resource).and_raise(Kubeclient::ResourceNotFoundError.new(1, "", 2))
        expect(@kubeapi).to receive(:apply_resource).and_return(resource)
        etl.kube_apply(parsed_yml)
        expect(etl.instance_variable_get(:@wrote_crds)).to eq(true)
      end

      it "registers project mapping writes on updated resource" do
        resource_yml = <<~EOF
          apiVersion: v1
          kind: ProjectMapping
          metadata:
            name: "pm1"
          spec:
            "scope": "override"
        EOF
        parsed_yml = YAML.load(resource_yml)
        resource = Kubeclient::Resource.new(parsed_yml.merge(metadata: {resourceVersion: "123"}))

        expect(etl.instance_variable_get(:@wrote_crds)).to eq(false)
        expect(@kubeapi).to receive(:get_resource).and_return(resource)
        expect(@kubeapi).to receive(:apply_resource).and_return(resource)
        etl.kube_apply(parsed_yml)
        expect(etl.instance_variable_get(:@wrote_crds)).to eq(false)

        resource.metadata.resourceVersion = "456"
        expect(@kubeapi).to receive(:apply_resource).and_return(resource)
        etl.kube_apply(parsed_yml)
        expect(etl.instance_variable_get(:@wrote_crds)).to eq(true)
      end

    end

    describe "#apply" do

      let(:collection) { ProjectCollection.new }
      let(:root_spec_crd) { default_root_spec }
      let(:config) {
        Kubetruth::Config.new([root_spec_crd])
      }

      before(:each) do
        allow(CtApi).to receive(:reset)

        @ns = "primary-ns"
        allow(@kubeapi).to receive(:namespace).and_return(@ns)
        allow(ProjectCollection).to receive(:new).and_return(collection)
        allow(collection).to receive(:create_project).and_wrap_original do |m, *args|
          project = m.call(*args)
          allow(project).to receive(:parameters).and_return([
                                                              Parameter.new(key: "param1", value: "value1", secret: false),
                                                              Parameter.new(key: "param2", value: "value2", secret: true)
                                                            ])
          project
        end
      end

      it "renders multiple templates" do
        allow(etl).to receive(:load_config).and_yield(@ns, config)

        expect(collection).to receive(:names).and_return(["proj1"])

        expect(etl).to receive(:kube_apply).with(hash_including("kind" => "ConfigMap"))
        expect(etl).to receive(:kube_apply).with(hash_including("kind" => "Secret"))

        etl.apply()
      end

      it "renders a stream of templates" do
        config.root_spec.resource_templates = {"name1" => Template.new("stream_item: one\n---\nstream_item: two\n")}
        allow(etl).to receive(:load_config).and_yield(@ns, config)

        expect(collection).to receive(:names).and_return(["proj1"])

        expect(etl).to receive(:kube_apply).with(hash_including("stream_item" => "one"))
        expect(etl).to receive(:kube_apply).with(hash_including("stream_item" => "two"))

        etl.apply()
      end

      it "skips empty templates" do
        config.root_spec.resource_templates = {"name1" => Template.new("\n\n   \n")}
        allow(etl).to receive(:load_config).and_yield(@ns, config)

        expect(collection).to receive(:names).and_return(["proj1"])

        expect(etl).to_not receive(:kube_apply)

        etl.apply()
        expect(Logging.contents).to match(/Skipping empty template/)
      end

      it "allows dryrun" do
        etl = described_class.new(dry_run: true)
        allow(etl).to receive(:load_config).and_yield(@ns, config)
        expect(collection).to receive(:names).and_return(["proj1"])

        expect(@kubeapi).to receive(:get_resource)
        expect(@kubeapi).to_not receive(:ensure_namespace)
        expect(@kubeapi).to_not receive(:apply_resource)

        etl.apply()
        expect(Logging.contents).to match("Performing dry-run")
      end

      it "skips projects when selector fails" do
        config.root_spec.project_selector = /oo/
        allow(etl).to receive(:load_config).and_yield(@ns, config)
        expect(collection).to receive(:names).and_return(["proj1", "foo", "bar"])

        expect(etl).to receive(:kube_apply).with(hash_including("metadata" => hash_including("name" => "foo"))).twice

        etl.apply()
      end

      it "skips projects if flag is set" do
        conf = Kubetruth::Config.new([root_spec_crd, {scope: "override", project_selector: "foo", skip: true}])
        allow(etl).to receive(:load_config).and_yield(@ns, conf)

        expect(collection).to receive(:names).and_return(["proj1", "foo", "bar"])

        expect(etl).to receive(:kube_apply).with(hash_including("metadata" => hash_including("name" => "foo"))).never
        expect(etl).to receive(:kube_apply).with(hash_including("metadata" => hash_including("name" => "proj1"))).twice
        expect(etl).to receive(:kube_apply).with(hash_including("metadata" => hash_including("name" => "bar"))).twice

        etl.apply()
      end

      it "allows included projects not selected by selector" do
        config.root_spec.project_selector = /proj1/
        config.root_spec.included_projects = ["proj2"]
        allow(etl).to receive(:load_config).and_yield(@ns, config)

        expect(collection).to receive(:names).and_return(["proj1", "proj2", "proj3"])

        allow(etl).to receive(:kube_apply)
        expect(config.root_spec.resource_templates.values.first).to receive(:render) do |*args, **kwargs|
          expect(kwargs[:project]).to eq("proj1")
          expect(kwargs[:project_heirarchy]).to eq({"proj1"=>{"proj2"=>{}}})
          expect(kwargs[:parameter_origins]).to eq({"param1"=>"proj1 (proj2)"})
          ""
        end

        etl.apply()
      end

      it "allows projects not selected by root selector" do
        conf = Kubetruth::Config.new([root_spec_crd, {scope: "override", project_selector: "proj2"}])
        conf.root_spec.project_selector = /proj1/
        allow(etl).to receive(:load_config).and_yield(@ns, conf)

        expect(collection).to receive(:names).and_return(["proj2"])

        expect(etl).to receive(:kube_apply).with(hash_including("metadata" => hash_including("name" => "proj2"))).twice

        etl.apply()
      end

      it "renders templates with variables" do
        allow(etl).to receive(:load_config).and_yield(@ns, config)
        expect(collection).to receive(:names).and_return(["proj1"])

        allow(etl).to receive(:kube_apply)
        expect(config.root_spec.resource_templates.values.first).to receive(:render) do |*args, **kwargs|
          expect(kwargs[:template]).to eq("configmap")
          expect(kwargs[:kubetruth_namespace]).to eq(@ns)
          expect(kwargs[:mapping_namespace]).to eq(@ns)
          expect(kwargs[:project]).to eq("proj1")
          expect(kwargs[:project_heirarchy]).to eq(collection.projects["proj1"].heirarchy)
          expect(kwargs[:debug]).to eq(etl.logger.debug?)
          expect(kwargs[:parameters]).to eq({"param1"=>"value1"})
          expect(kwargs[:parameter_origins]).to eq({"param1"=>"proj1"})
          expect(kwargs[:secrets]).to eq({"param2"=>"value2"})
          expect(kwargs[:secret_origins]).to eq({"param2"=>"proj1"})
          expect(kwargs[:templates]).to be_an_instance_of(Template::TemplatesDrop)
          expect(kwargs[:context]).to match(hash_including(:resource_name, :resource_namespace))
          ""
        end

        etl.apply()
      end

      it "skips params with nil values" do
        allow(etl).to receive(:load_config).and_yield(@ns, config)
        expect(collection).to receive(:names).and_return(["proj1"])
        allow(collection).to receive(:create_project).and_wrap_original do |m, *args|
          project = m.call(*args)
          allow(project).to receive(:parameters).and_return([
                                                              Parameter.new(key: "param1", value: "value1", secret: false),
                                                              Parameter.new(key: "param2", value: "value2", secret: true),
                                                              Parameter.new(key: "param3", value: nil, secret: false),
                                                              Parameter.new(key: "param4", value: nil, secret: true)
                                                            ])
          project
        end

        allow(etl).to receive(:kube_apply)
        expect(config.root_spec.resource_templates.values.first).to receive(:render) do |*args, **kwargs|
          expect(kwargs[:parameters]).to eq({"param1"=>"value1"})
          expect(kwargs[:parameter_origins]).to eq({"param1"=>"proj1", "param3"=>"proj1"})
          expect(kwargs[:secrets]).to eq({"param2"=>"value2"})
          expect(kwargs[:secret_origins]).to eq({"param2"=>"proj1", "param4"=>"proj1"})
          ""
        end

        etl.apply()
      end
    end

    describe "default templates" do

      let(:collection) { ProjectCollection.new }
      let(:root_spec_crd) {
        default_root_spec = YAML.load_file(File.expand_path("../../helm/kubetruth/values.yaml", __dir__)).deep_symbolize_keys
        default_root_spec[:projectMappings][:root]
      }
      let(:config) {
        Kubetruth::Config.new([root_spec_crd])
      }

      before(:each) do
        allow(CtApi).to receive(:reset)

        @ns = "primary-ns"
        allow(@kubeapi).to receive(:namespace).and_return(@ns)
        allow(ProjectCollection).to receive(:new).and_return(collection)
        allow(collection).to receive(:create_project).and_wrap_original do |m, *args|
          project = m.call(*args)
          allow(project).to receive(:parameters).and_return([
                                                              Parameter.new(key: "param1", value: "value1", secret: false),
                                                              Parameter.new(key: "param2", value: "value2", secret: true)
                                                            ])
          project
        end
        allow(collection).to receive(:names).and_return(["proj1"])
        allow(etl).to receive(:kube_apply)
      end

      it "sets config and secrets in default template" do
        allow(etl).to receive(:load_config).and_yield(@ns, config)

        allow(etl).to receive(:kube_apply) do |parsed_yml|
          if parsed_yml["kind"] == "ConfigMap"
            expect(parsed_yml["data"]['param1']).to eq("value1")
            expect(parsed_yml["data"].has_key?('param2')).to be false
          elsif parsed_yml["kind"] == "Secret"
            expect(parsed_yml["data"]['param2']).to eq(Base64.strict_encode64('value2'))
            expect(parsed_yml["data"].has_key?('param1')).to be false
          else
            raise "Unexpected kubernetes resource kind"
          end
        end.twice

        etl.apply()
      end

      it "skips secrets when set in context" do
        root_spec_crd[:context][:skip_secrets] = true
        conf = Kubetruth::Config.new([root_spec_crd])
        allow(etl).to receive(:load_config).and_yield(@ns, conf)

        expect(conf.root_spec.resource_templates["secret"]).to receive(:render).and_wrap_original do |m, *args, **kwargs|
          result = m.call(*args, **kwargs)
          expect(result).to be_blank
          result
        end

        etl.apply()
      end

      it "sets log level when supplied by root pm in config" do
        Kubetruth::Logging.root_log_level = "error" # undo debug logging set by test harness
        config.root_spec.log_level = "error"

        allow(etl).to receive(:load_config).and_yield(@ns, config)
        allow(config.root_spec.resource_templates["configmap"]).to receive(:render).and_return("")

        etl.apply()
        expect(Logging.contents).to_not match(/DEBUG/)
        Logging.clear

        config.root_spec.log_level = "debug"
        etl.apply()
        expect(Logging.contents).to match(/DEBUG/)
      end

      it "sets log level when supplied by override pm in config" do
        Kubetruth::Logging.root_log_level = "error" # undo debug logging set by test harness

        override_crd = {scope: "override", project_selector: "proj1", log_level: "debug"}
        config = Kubetruth::Config.new([root_spec_crd, override_crd])

        allow(etl).to receive(:load_config).and_yield(@ns, config)
        allow(config.root_spec.resource_templates["configmap"]).to receive(:render).and_return("")

        etl.apply()
        expect(Logging.contents).to_not match(/DEBUG.*Config ProjectSpec for root mapping/)
        expect(Logging.contents).to match(/INFO.*ETL Processing project 'proj1'/)
        expect(Logging.contents).to match(/DEBUG.*Template Evaluating template/)
      end


    end

    describe "verify async behavior" do

      it "logs exceptions" do
        task = etl.async(annotation: "badtask") do
          raise "task fail"
        end
        expect(Logging.contents).to match(/ERROR ETL \[exception=RuntimeError \] Failure in async task: badtask/)
        expect(task.status).to eq(:stopped)
      end

      it "yields task" do
        etl.async(annotation: "mytask") do |task|
          expect(task.annotation).to eq("mytask")
        end
      end

    end

  end
end
