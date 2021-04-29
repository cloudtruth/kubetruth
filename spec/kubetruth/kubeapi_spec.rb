require 'rspec'
require 'kubetruth/kubeapi'
require 'kubetruth/config'

module Kubetruth

  describe KubeApi, :vcr => {
      # uncomment (or delete vcr yml file) to force record of new fixtures
      # :record => :all,
      # minikube has variable port for api server url, so use match_requests_on to not match against port
      :match_requests_on => [:method, :host, :path]
  } do

    def namespace; "kubetruth-test-ns"; end
    def helm_name; "kubetruth-test-app"; end

    if ! ENV['CI']

      def check_deps
        @deps_checked ||= begin
          system("helm version >/dev/null 2>&1") || fail("test dependency not installed - helm ")
          system("minikube version >/dev/null 2>&1") || fail("test dependency not installed - minikube")
          system("minikube status >/dev/null 2>&1") || fail("test dependency nor running - minikube")
          true
        end
      end

      def teardown
        sysrun("helm delete --namespace #{namespace} #{helm_name}", output_on_fail: false, allow_fail: true)
        existing_namespaces.each do |ns|
          sysrun("minikube kubectl -- delete namespace #{ns}", output_on_fail: false, allow_fail: true)
        end
      end

      def setup
        check_deps
        teardown
        root = File.expand_path('../..', __dir__)
        sysrun("helm install --create-namespace --namespace #{namespace} --set appSettings.apiKey=#{ENV['CT_API_KEY']} #{helm_name} #{root}/helm/kubetruth/")
      end

      def token
        @token ||= begin
          secret_names = sysrun("minikube kubectl -- --namespace #{namespace} get secret").lines
          secret_names = secret_names.grep(/#{helm_name}-token/)
          secret_name = secret_names.first.split.first
          token_lines = sysrun("minikube kubectl -- --namespace #{namespace} describe secret #{secret_name}").lines
          token_lines = token_lines.grep(/token:/)
          token_lines.first.split[1]
        end
      end

      def apiserver
        @apiserver ||= begin
          config = YAML.load(sysrun("minikube kubectl -- config view"))
          cluster = config["clusters"].find {|c| c["name"] == "minikube" }
          cluster["cluster"]["server"]
        end
      end

      def existing_namespaces
        names = sysrun("minikube kubectl -- get namespace").lines
        names = names.grep(/#{namespace}/)
        names = names.collect {|n| n.split.first }
        names
      end

      before(:all) do
        setup
      end

      after(:all) do
        teardown
      end

    else

      def token; ""; end
      def apiserver; "https://127.0.0.1"; end

    end

    let(:kubeapi) { described_class.new(namespace: namespace, token: token, api_url: apiserver) }

    describe "initialize" do

      it "uses supplied namespace" do
        expect(described_class.new(namespace: "foo").namespace).to eq("foo")
      end

    end

    describe "ensure_namespace" do

      it "creates namespace if not present" do
        kapi = described_class.new(namespace: "#{namespace}-newns", token: token, api_url: apiserver)
        expect { kapi.create_config_map("foo", {}) }.to raise_error(Kubeclient::ResourceNotFoundError, /namespaces.*not found/)
        ns = kapi.ensure_namespace
        kapi.create_config_map("foo", {bar: "baz"})
        expect(kapi.get_config_map("foo").data["bar"]).to eq("baz")
      end

      it "sets labels when creating namespace" do
        kapi = described_class.new(namespace: "#{namespace}-newns2", token: token, api_url: apiserver)
        expect { kapi.create_config_map("foo", {}) }.to raise_error(Kubeclient::ResourceNotFoundError, /namespaces.*not found/)
        ns = kapi.ensure_namespace
        expect(ns.metadata.labels.to_h).to eq({:"app.kubernetes.io/managed-by" => "kubetruth"})
      end

    end

    describe "under_management?" do

      it "handles empty labels" do
        resource = Kubeclient::Resource.new
        expect(kubeapi.under_management?(resource)).to eq(false)
      end

      it "handles missing labels" do
        resource = Kubeclient::Resource.new
        resource.metadata = {}
        resource.metadata.labels = {foo: "bar"}
        expect(kubeapi.under_management?(resource)).to eq(false)
      end

      it "handles correct labels" do
        resource = Kubeclient::Resource.new
        resource.metadata = {}
        resource.metadata.labels = {KubeApi::MANAGED_LABEL_KEY => KubeApi::MANAGED_LABEL_VALUE}
        expect(kubeapi.under_management?(resource)).to eq(true)
      end

    end

    describe "secret_hash" do

      it "handles empty data" do
        resource = Kubeclient::Resource.new
        expect(kubeapi.secret_hash(resource)).to eq({})
      end

      it "decodes secret data" do
        resource = Kubeclient::Resource.new
        resource.data = {foo: Base64.encode64("bar")}
        expect(kubeapi.secret_hash(resource)).to eq({foo: "bar"})
      end

    end

    describe "configmaps" do

      it "can crud config maps" do
        expect { kubeapi.get_config_map("foo") }.to raise_error(Kubeclient::ResourceNotFoundError)
        cm = kubeapi.create_config_map("foo", {bar: "baz"})
        expect(kubeapi.get_config_map_names).to include("foo")
        expect(kubeapi.get_config_map("foo").data["bar"]).to eq("baz")
        kubeapi.update_config_map("foo", {bar: "bum"})
        expect(kubeapi.get_config_map("foo").data["bar"]).to eq("bum")
        kubeapi.delete_config_map("foo")
        expect { kubeapi.get_config_map("foo") }.to raise_error(Kubeclient::ResourceNotFoundError)
      end

      it "can use multiple namespaces for config maps" do
        ns1_kapi = described_class.new(namespace: "#{namespace}-cmns1", token: token, api_url: apiserver)
        ns1_kapi.ensure_namespace
        ns2_kapi = described_class.new(namespace: "#{namespace}-cmns2", token: token, api_url: apiserver)
        ns2_kapi.ensure_namespace

        expect { ns1_kapi.get_config_map("foo") }.to raise_error(Kubeclient::ResourceNotFoundError)
        cm = ns1_kapi.create_config_map("foo", {bar: "baz"})
        expect(ns1_kapi.get_config_map_names).to include("foo")
        expect(ns1_kapi.get_config_map("foo").data["bar"]).to eq("baz")
        ns1_kapi.update_config_map("foo", {bar: "bum"})
        expect(ns1_kapi.get_config_map("foo").data["bar"]).to eq("bum")
        ns1_kapi.delete_config_map("foo")
        expect { ns1_kapi.get_config_map("foo") }.to raise_error(Kubeclient::ResourceNotFoundError)

        expect { ns2_kapi.get_config_map("foo") }.to raise_error(Kubeclient::ResourceNotFoundError)
        cm = ns2_kapi.create_config_map("foo", {bar: "baz"})
        expect(ns2_kapi.get_config_map_names).to include("foo")
        expect(ns2_kapi.get_config_map("foo").data["bar"]).to eq("baz")
        ns2_kapi.update_config_map("foo", {bar: "bum"})
        expect(ns2_kapi.get_config_map("foo").data["bar"]).to eq("bum")
        ns2_kapi.delete_config_map("foo")
        expect { ns2_kapi.get_config_map("foo") }.to raise_error(Kubeclient::ResourceNotFoundError)
      end

      it "sets labels when creating config maps" do
        expect { kubeapi.get_config_map("bar") }.to raise_error(Kubeclient::ResourceNotFoundError)
        cm = kubeapi.create_config_map("bar", {bar: "baz"})
        expect(kubeapi.get_config_map_names).to include("bar")
        expect(cm.metadata.labels.to_h).to eq({:"app.kubernetes.io/managed-by" => "kubetruth"})
      end

      it "sets labels when updating config maps" do
        expect { kubeapi.get_config_map("baz") }.to raise_error(Kubeclient::ResourceNotFoundError)
        cm = kubeapi.create_config_map("baz", {bar: "baz"})
        cm.metadata.labels = {"otherlabel" => "set"}
        kubeapi.client.update_config_map(cm)

        cm = kubeapi.update_config_map("baz", {bum: "boo"})
        expect(cm.metadata.labels.to_h).to eq({:"app.kubernetes.io/managed-by" => "kubetruth", :"otherlabel" => "set"})
      end

    end

    describe "secrets" do

      it "can crud secrets" do
        expect { kubeapi.get_secret("foo") }.to raise_error(Kubeclient::ResourceNotFoundError)
        secret = kubeapi.create_secret("foo", {bar: "baz"})
        expect(kubeapi.get_secret_names).to include("foo")
        resource = kubeapi.get_secret("foo")
        data = kubeapi.secret_hash(resource)
        expect(data).to eq({bar: "baz"})
        kubeapi.update_secret("foo", {bar: "bum"})
        resource = kubeapi.get_secret("foo")
        data = kubeapi.secret_hash(resource)
        expect(data).to eq({bar: "bum"})
        kubeapi.delete_secret("foo")
        expect { kubeapi.get_secret("foo") }.to raise_error(Kubeclient::ResourceNotFoundError)
      end

      it "can use multiple namespaces for secrets" do
        ns1_kapi = described_class.new(namespace: "#{namespace}-secretns1", token: token, api_url: apiserver)
        ns1_kapi.ensure_namespace
        ns1_kapi.ensure_namespace
        ns2_kapi = described_class.new(namespace: "#{namespace}-secretns2", token: token, api_url: apiserver)
        ns2_kapi.ensure_namespace

        expect { ns1_kapi.get_secret("foo") }.to raise_error(Kubeclient::ResourceNotFoundError)
        secret = ns1_kapi.create_secret("foo", {bar: "baz"})
        expect(ns1_kapi.get_secret_names).to include("foo")
        resource = ns1_kapi.get_secret("foo")
        data = ns1_kapi.secret_hash(resource)
        expect(data).to eq({bar: "baz"})
        ns1_kapi.update_secret("foo", {bar: "bum"})
        resource = ns1_kapi.get_secret("foo")
        data = ns1_kapi.secret_hash(resource)
        expect(data).to eq({bar: "bum"})
        ns1_kapi.delete_secret("foo")
        expect { ns1_kapi.get_secret("foo") }.to raise_error(Kubeclient::ResourceNotFoundError)

        expect { ns2_kapi.get_secret("foo") }.to raise_error(Kubeclient::ResourceNotFoundError)
        secret = ns2_kapi.create_secret("foo", {bar: "baz"})
        expect(ns2_kapi.get_secret_names).to include("foo")
        resource = ns2_kapi.get_secret("foo")
        data = ns2_kapi.secret_hash(resource)
        expect(data).to eq({bar: "baz"})
        ns2_kapi.update_secret("foo", {bar: "bum"})
        resource = ns2_kapi.get_secret("foo")
        data = ns2_kapi.secret_hash(resource)
        expect(data).to eq({bar: "bum"})
        ns2_kapi.delete_secret("foo")
        expect { ns2_kapi.get_secret("foo") }.to raise_error(Kubeclient::ResourceNotFoundError)
      end

      it "sets labels when creating secrets" do
        expect { kubeapi.get_secret("bar") }.to raise_error(Kubeclient::ResourceNotFoundError)
        secret = kubeapi.create_secret("bar", {bar: "baz"})
        expect(kubeapi.get_secret_names).to include("bar")
        expect(secret.metadata.labels.to_h).to eq({:"app.kubernetes.io/managed-by" => "kubetruth"})
      end

      it "sets labels when updating secrets" do
        expect { kubeapi.get_secret("baz") }.to raise_error(Kubeclient::ResourceNotFoundError)
        secret = kubeapi.create_secret("baz", {bar: "baz"})
        secret.metadata.labels = {"otherlabel" => "set"}
        kubeapi.client.update_secret(secret)

        secret = kubeapi.update_secret("baz", {bum: "boo"})
        expect(secret.metadata.labels.to_h).to eq({:"app.kubernetes.io/managed-by" => "kubetruth", :"otherlabel" => "set"})
      end

    end

    describe "custom resource" do

      it "can get project mappings" do
        crds = kubeapi.get_project_mappings
        expect(crds.size).to eq(1) # from helm install
        expect(crds.first.keys.sort).to eq(Kubetruth::Config::ProjectSpec.new.to_h.keys.sort)
      end

      it "can watch project mappings" do
        skip("only works when vcr/webmock disabled")

        test_mapping_name = "test-mapping-watch"
        mapping_data = <<~EOF
          apiVersion: kubetruth.cloudtruth.com/v1
          kind: ProjectMapping
          metadata:
              name: #{test_mapping_name}
          spec:
              scope: override
              project_selector: "^notme$"
        EOF

        # p kubeapi.crdclient.get_project_mappings(namespace: namespace).resourceVersion
        # p kubeapi.crdclient.get_project_mappings(namespace: namespace).collect {|r| r.metadata.name }
        # p kubeapi.get_project_mappings

        watcher = kubeapi.watch_project_mappings
        begin
          Thread.new do
            watcher.each do |notice|
              # p notice.type
              # p notice.object.metadata.name
              # p notice.object
              expect(notice.object.metadata.name).to eq(test_mapping_name)
              break
            end
          end

          sleep(1)

          # need an admin token for this to work or temporarily add to
          # projectmappings permissions on installed role
          resource = Kubeclient::Resource.new
          resource.metadata = {}
          resource.metadata.name = test_mapping_name
          resource.metadata.namespace = namespace
          resource.spec = {scope: "override", project_selector: "^notme$"}
          kubeapi.crdclient.create_project_mapping(resource)

          # sysrun(%Q[minikube kubectl -- --namespace #{namespace} patch pm kubetruth-test-app-root --type json --patch '[{"op": "replace", "path": "/spec/included_projects", "value": ["Base"]}]'])
          # sysrun(%Q[minikube kubectl -- --namespace #{namespace} apply -f -], stdin_data: mapping_data)
          sleep(1)
        ensure
          watcher.finish
        end
      end

    end

  end
end
