require 'rspec'
require 'kubetruth/etl'

module Kubetruth
  describe ETL do

    let(:init_args) {{
        key_prefixes: [""], key_patterns: [/./],
        name_template: "%s", key_template: "%s",
        ct_context: {}, kube_context: {}
    }}

    before(:each) do
      @ctapi_class = Class.new
      @ctapi = double()
      allow(Kubetruth).to receive(:CtApi).and_return(@ctapi_class)
      allow(@ctapi_class).to receive(:new).and_return(@ctapi)

      @kubeapi = double(Kubetruth::KubeApi)
      allow(Kubetruth::KubeApi).to receive(:new).and_return(@kubeapi)
      allow(@kubeapi).to receive(:get_config_map_names).and_return([])
      allow(@kubeapi).to receive(:get_secret_names).and_return([])
    end

    describe "#ctapi" do

      it "is memoized" do
        etl = described_class.new(init_args)
        expect(etl.ctapi).to equal(etl.ctapi)
      end

    end

    describe "#kubeapi" do

      it "is memoized" do
        etl = described_class.new(init_args)
        expect(etl.kubeapi).to equal(etl.kubeapi)
      end

    end

    describe "#partition_secrets" do

      it "handles empty" do
        etl = described_class.new(init_args)
        configs, secrets = etl.partition_secrets({})
        expect(configs).to eq({})
        expect(secrets).to eq({})
      end

      it "segregates secret params into their own hash" do
        etl = described_class.new(init_args)
        param_groups = {
            group1: [
                Parameter.new(key: "param1", value: "value1", secret: false),
                Parameter.new(key: "param2", value: "value2", secret: false)
            ],
            group2: [
                Parameter.new(key: "param3", value: "value3", secret: true),
                Parameter.new(key: "param4", value: "value4", secret: false)
            ]
        }
        config, secrets = etl.partition_secrets(param_groups)
        expect(config.keys).to eq(param_groups.keys)
        expect(config.values.flatten.collect(&:key)).to eq(["param1", "param2", "param4"])
        expect(secrets.keys).to eq([:group2])
        expect(secrets.values.flatten.collect(&:key)).to eq(["param3"])
      end

    end

    describe "#dns_friendly" do

      it "cleans up name" do
        etl = described_class.new(init_args)
        expect(etl.dns_friendly("foo_bar")).to eq("foo-bar")
      end

      it "simplifies successive non-chars" do
        etl = described_class.new(init_args)
        expect(etl.dns_friendly("foo_&!bar")).to eq("foo-bar")
      end

      it "strips leading/trailing non-chars" do
        etl = described_class.new(init_args)
        expect(etl.dns_friendly("_foo!bar_")).to eq("foo-bar")
      end

    end

    describe "#get_param_groups" do

      it "handles empty" do
        etl = described_class.new(init_args)
        expect(@ctapi).to receive(:parameters).and_return([])
        param_groups = etl.get_param_groups
        expect(param_groups).to eq({})
      end

      it "only selects for matching prefix" do
        etl = described_class.new(init_args.merge(key_prefixes: ["svc"]))
        expect(@ctapi).to receive(:parameters).and_return([
                                                              Parameter.new(key: "param1", value: "value1", secret: false),
                                                              Parameter.new(key: "svc.param2.foo", value: "value2", secret: false),
                                                              Parameter.new(key: "bar.svc.param3", value: "value3", secret: false),
                                                          ])
        param_groups = etl.get_param_groups
        expect(param_groups.values.flatten.size).to eq(1)
        expect(param_groups.values.flatten.collect(&:original_key)).to eq(["svc.param2.foo"])
      end

      it "selects for multiple prefixes" do
        etl = described_class.new(init_args.merge(key_prefixes: ["svc", "bar"]))
        expect(@ctapi).to receive(:parameters).with(searchTerm: "svc").and_return([
                                                              Parameter.new(key: "svc.param2.foo", value: "value2", secret: false),
                                                          ])
        expect(@ctapi).to receive(:parameters).with(searchTerm: "bar").and_return([
                                                              Parameter.new(key: "bar.svc.param3", value: "value3", secret: false),
                                                          ])
        param_groups = etl.get_param_groups
        expect(param_groups.values.flatten.size).to eq(2)
        expect(param_groups.values.flatten.collect(&:original_key)).to eq(["svc.param2.foo", "bar.svc.param3"])
      end

      it "only selects for matching pattern" do
        etl = described_class.new(init_args.merge(key_patterns: [/^(?<prefix>[^\.]+)\.(?<name>[^\.]+)\.(?<key>.*)/]))
        expect(@ctapi).to receive(:parameters).and_return([
                                                              Parameter.new(key: "svc.param1", value: "value1", secret: false),
                                                              Parameter.new(key: "svc.param2.foo", value: "value2", secret: false),
                                                          ])
        param_groups = etl.get_param_groups
        expect(param_groups.values.flatten.size).to eq(1)
        expect(param_groups.values.flatten.collect(&:original_key)).to eq(["svc.param2.foo"])
      end

      it "selects for multiple patterns" do
        etl = described_class.new(init_args.merge(key_patterns: [/^svc/, /^bar/]))
        expect(@ctapi).to receive(:parameters).and_return([
                                                              Parameter.new(key: "foo.param1", value: "value1", secret: false),
                                                              Parameter.new(key: "svc.param2.foo", value: "value2", secret: false),
                                                              Parameter.new(key: "bar.svc.param3", value: "value3", secret: false)
                                                          ])
        param_groups = etl.get_param_groups
        expect(param_groups.values.flatten.size).to eq(2)
        expect(param_groups.values.flatten.collect(&:original_key)).to eq(["svc.param2.foo", "bar.svc.param3"])
      end

      it "applies templates to matches" do
        etl = described_class.new(init_args.merge(
            key_patterns: [/^(?<prefix>[^\.]+)\.(?<name>[^\.]+)\.(?<key>.*)/],
            name_template: "%{name}",
            key_template: "%{key}"
        ))
        expect(@ctapi).to receive(:parameters).and_return([
                                                              Parameter.new(key: "svc.name1.key1", value: "value1", secret: false),
                                                              Parameter.new(key: "svc.name2.key2", value: "value2", secret: false)
                                                          ])
        param_groups = etl.get_param_groups
        expect(param_groups.size).to eq(2)
        expect(param_groups["name1"]).to eq([Parameter.new(original_key: "svc.name1.key1", key: "key1", value: "value1", secret: false)])
        expect(param_groups["name2"]).to eq([Parameter.new(original_key: "svc.name2.key2", key: "key2", value: "value2", secret: false)])
      end

      it "has a number of template options" do
        etl = described_class.new(init_args.merge(
            key_patterns: [/^(?<prefix>[^\.]+)\.(?<name>[^\.]+)\.(?<key>.*)/],
            name_template: "%{prefix}.%{name}",
            key_template: "start.%{key}.%{name}.%{prefix}.middle.%{key_upcase}.%{name_upcase}.%{prefix_upcase}.end"
        ))
        expect(@ctapi).to receive(:parameters).and_return([
                                                              Parameter.new(key: "svc.name1.key1", value: "value1", secret: false),
                                                          ])
        param_groups = etl.get_param_groups
        expect(param_groups.size).to eq(1)
        expect(param_groups["svc.name1"]).to eq([Parameter.new(original_key: "svc.name1.key1", key: "start.key1.name1.svc.middle.KEY1.NAME1.SVC.end", value: "value1", secret: false)])
      end

    end

    describe "#apply_config_maps" do

      it "calls kube to create new config map" do
        etl = described_class.new(init_args)
        param_groups = {
            group1: [
                Parameter.new(key: "param1", value: "value1", secret: false),
                Parameter.new(key: "param2", value: "value2", secret: false)
            ]
        }
        expect(@kubeapi).to receive(:get_config_map).with("group1").and_raise(Kubeclient::ResourceNotFoundError.new(1, "", 2))
        expect(@kubeapi).to_not receive(:update_config_map)
        expect(@kubeapi).to receive(:create_config_map).with("group1", {"param1" => "value1", "param2" => "value2"})
        etl.apply_config_maps(param_groups)
      end

      it "calls kube to update config map" do
        etl = described_class.new(init_args)
        param_groups = {
            group1: [
                Parameter.new(key: "param1", value: "value1", secret: false),
                Parameter.new(key: "param2", value: "value2", secret: false)
            ]
        }
        expect(@kubeapi).to receive(:get_config_map).with("group1").and_return({oldparam: "oldvalue"})
        expect(@kubeapi).to_not receive(:create_config_map)
        expect(@kubeapi).to receive(:update_config_map).with("group1", {"param1" => "value1", "param2" => "value2"})
        etl.apply_config_maps(param_groups)
      end

      it "doesn't update config map if data same" do
        etl = described_class.new(init_args)
        param_groups = {
            group1: [
                Parameter.new(key: "param1", value: "value1", secret: false),
                Parameter.new(key: "param2", value: "value2", secret: false)
            ]
        }
        expect(@kubeapi).to receive(:get_config_map).with("group1").and_return({param1: "value1", param2: "value2"})
        expect(@kubeapi).to_not receive(:create_config_map)
        expect(@kubeapi).to_not receive(:update_config_map)
        etl.apply_config_maps(param_groups)
      end

    end

    describe "#apply_secrets" do

      it "calls kube to create new secret" do
        etl = described_class.new(init_args)
        param_groups = {
            group1: [
                Parameter.new(key: "param1", value: "value1", secret: true),
                Parameter.new(key: "param2", value: "value2", secret: true)
            ]
        }
        expect(@kubeapi).to receive(:get_secret).with("group1").and_raise(Kubeclient::ResourceNotFoundError.new(1, "", 2))
        expect(@kubeapi).to_not receive(:update_secret)
        expect(@kubeapi).to receive(:create_secret).with("group1", {"param1" => "value1", "param2" => "value2"})
        etl.apply_secrets(param_groups)
      end

      it "calls kube to update secret" do
        etl = described_class.new(init_args)
        param_groups = {
            group1: [
                Parameter.new(key: "param1", value: "value1", secret: true),
                Parameter.new(key: "param2", value: "value2", secret: true)
            ]
        }
        expect(@kubeapi).to receive(:get_secret).with("group1").and_return({oldparam: "oldvalue"})
        expect(@kubeapi).to_not receive(:create_secret)
        expect(@kubeapi).to receive(:update_secret).with("group1", {"param1" => "value1", "param2" => "value2"})
        etl.apply_secrets(param_groups)
      end

      it "doesn't update secret if data same" do
        etl = described_class.new(init_args)
        param_groups = {
            group1: [
                Parameter.new(key: "param1", value: "value1", secret: true),
                Parameter.new(key: "param2", value: "value2", secret: true)
            ]
        }
        expect(@kubeapi).to receive(:get_secret).with("group1").and_return({param1: "value1", param2: "value2"})
        expect(@kubeapi).to_not receive(:create_secret)
        expect(@kubeapi).to_not receive(:update_secret)
        etl.apply_secrets(param_groups)
      end

    end

    describe "#apply" do

      it "sets config and secrets" do
        etl = described_class.new(init_args)
        param_groups = {
            "group1" => [
                Parameter.new(key: "param1", value: "value1", secret: false),
                Parameter.new(key: "param2", value: "value2", secret: true)
            ]
        }
        expect(etl).to receive(:get_param_groups).and_return(param_groups)
        expect(etl).to receive(:apply_config_maps).with({"group1" => [param_groups["group1"][0]]})
        expect(etl).to receive(:apply_secrets).with({"group1" => [param_groups["group1"][1]]})
        etl.apply()
      end

      it "sets secrets as config" do
        etl = described_class.new(init_args)
        param_groups = {
            "group1" => [
                Parameter.new(key: "param1", value: "value1", secret: false),
                Parameter.new(key: "param2", value: "value2", secret: true)
            ]
        }
        expect(etl).to receive(:get_param_groups).and_return(param_groups)
        expect(etl).to receive(:apply_config_maps).with(param_groups)
        expect(etl).to receive(:apply_secrets).never
        etl.apply(secrets_as_config: true)
      end

      it "skips secrets" do
        etl = described_class.new(init_args)
        param_groups = {
            "group1" => [
                Parameter.new(key: "param1", value: "value1", secret: false),
                Parameter.new(key: "param2", value: "value2", secret: true)
            ]
        }
        expect(etl).to receive(:get_param_groups).and_return(param_groups)
        expect(etl).to receive(:apply_config_maps).with({"group1" => [param_groups["group1"][0]]})
        expect(etl).to receive(:apply_secrets).never
        etl.apply(skip_secrets: true)
      end

      it "allows dryrun" do
        etl = described_class.new(init_args)
        param_groups = {
            "group1" => [
                Parameter.new(key: "param1", value: "value1", secret: false),
                Parameter.new(key: "param2", value: "value2", secret: true)
            ]
        }
        expect(etl).to receive(:get_param_groups).and_return(param_groups)
        expect(etl).to receive(:apply_config_maps).never
        expect(etl).to receive(:apply_secrets).never
        etl.apply(dry_run: true)
        expect(Logging.contents).to match("Performing dry-run")
      end

    end

  end
end
