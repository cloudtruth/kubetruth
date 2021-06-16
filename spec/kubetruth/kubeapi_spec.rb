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
        sysrun("helm install --create-namespace --namespace #{namespace} --set appSettings.apiKey=#{ENV['CLOUDTRUTH_API_KEY']} #{helm_name} #{root}/helm/kubetruth/")
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

    before(:each) do |ex|
      # gives us a unique name that is consistent across runs of the same spec
      # so VCR fixture stays valid
      @spec_name = "#{self.class.name}#{ex.description}".downcase.gsub(/[^\w]+/, "-")
    end

    describe "initialize" do

      it "uses supplied namespace" do
        expect(described_class.new(namespace: "foo").namespace).to eq("foo")
      end

    end

    describe "ensure_namespace" do

      it "creates namespace if not present" do
        kapi = described_class.new(namespace: "#{namespace}-newns", token: token, api_url: apiserver)

        expect { kapi.client.get_namespace(kapi.namespace) }.to raise_error(Kubeclient::ResourceNotFoundError, /namespaces.*not found/)
        kapi.ensure_namespace
        ns = kapi.client.get_namespace(kapi.namespace)
        expect(ns.kind).to eq("Namespace")
        expect(ns.metadata.name).to eq(kapi.namespace)
      end

      it "sets labels when creating namespace" do
        kapi = described_class.new(namespace: "#{namespace}-newns2", token: token, api_url: apiserver)
        expect { kapi.client.get_namespace(kapi.namespace) }.to raise_error(Kubeclient::ResourceNotFoundError, /namespaces.*not found/)
        ns = kapi.ensure_namespace
        expect(ns.metadata.labels.to_h).to match(hash_including(KubeApi::MANAGED_LABEL_KEY.to_sym => KubeApi::MANAGED_LABEL_VALUE))
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

    describe "set_managed" do

      it "handles empty labels" do
        resource = Kubeclient::Resource.new
        kubeapi.set_managed(resource)
        expect(resource.metadata.labels.to_h).to eq(KubeApi::MANAGED_LABEL_KEY.to_sym => KubeApi::MANAGED_LABEL_VALUE)
      end

      it "handles missing labels" do
        resource = Kubeclient::Resource.new
        resource.metadata = {}
        resource.metadata.labels = {foo: "bar"}
        kubeapi.set_managed(resource)
        expect(resource.metadata.labels.to_h).to eq(foo: "bar", KubeApi::MANAGED_LABEL_KEY.to_sym => KubeApi::MANAGED_LABEL_VALUE)
      end

      it "handles correct labels" do
        resource = Kubeclient::Resource.new
        resource.metadata = {}
        resource.metadata.labels = {KubeApi::MANAGED_LABEL_KEY => KubeApi::MANAGED_LABEL_VALUE}
        kubeapi.set_managed(resource)
        expect(resource.metadata.labels.to_h).to eq({KubeApi::MANAGED_LABEL_KEY.to_sym => KubeApi::MANAGED_LABEL_VALUE})
      end

    end

    describe "get_resource" do

      it "raise when resource doesn't exist" do
        expect { kubeapi.get_resource("configmaps", @spec_name) }.to raise_error(Kubeclient::ResourceNotFoundError)
      end

      it "gets existing resource" do
        expect { kubeapi.get_resource("configmaps", @spec_name) }.to raise_error(Kubeclient::ResourceNotFoundError)

        resource = Kubeclient::Resource.new(metadata: {name: @spec_name, namespace: kubeapi.namespace}, data: {bar: "baz"})
        kubeapi.client.create_config_map(resource)

        fetched_resource = kubeapi.get_resource("configmaps", @spec_name)
        expect(fetched_resource.metadata.name).to eq(@spec_name)
      end

    end

    describe "apply_resource" do

      it "creates a resource using client namespace" do
        expect { kubeapi.get_resource("configmaps", @spec_name) }.to raise_error(Kubeclient::ResourceNotFoundError)

        resource = Kubeclient::Resource.new(apiVersion: "v1", kind: "ConfigMap", metadata: {name: @spec_name}, data: {bar: "baz"})
        kubeapi.apply_resource(resource)

        fetched_resource = kubeapi.get_resource("configmaps", @spec_name)
        expect(fetched_resource.metadata.namespace).to eq(kubeapi.namespace)
        expect(fetched_resource.metadata.name).to eq(@spec_name)
        expect(fetched_resource.data.to_h).to eq({bar: "baz"})
      end

      it "creates a resource with supplied namespace" do
        kapi = described_class.new(namespace: "#{namespace}-arns", token: token, api_url: apiserver)
        kapi.ensure_namespace
        ns = kapi.namespace

        expect { kubeapi.get_resource("configmaps", @spec_name, ns) }.to raise_error(Kubeclient::ResourceNotFoundError)

        resource = Kubeclient::Resource.new(apiVersion: "v1", kind: "ConfigMap", metadata: {namespace: ns, name: @spec_name}, data: {bar: "baz"})
        kubeapi.apply_resource(resource)

        fetched_resource = kubeapi.get_resource("configmaps", @spec_name, ns)
        expect(fetched_resource.metadata.namespace).to eq(ns)
        expect(fetched_resource.metadata.name).to eq(@spec_name)
      end

      it "creates a resource from hash" do
        expect { kubeapi.get_resource("configmaps", @spec_name) }.to raise_error(Kubeclient::ResourceNotFoundError)

        resource = { apiVersion: "v1", kind: "ConfigMap", metadata: { name: @spec_name }, data: { bar: "baz" } }
        kubeapi.apply_resource(resource)

        fetched_resource = kubeapi.get_resource("configmaps", @spec_name)
        expect(fetched_resource.metadata.namespace).to eq(kubeapi.namespace)
        expect(fetched_resource.metadata.name).to eq(@spec_name)
        expect(fetched_resource.data.to_h).to eq({bar: "baz"})
      end

      it "sets up management when creating a resource" do
        expect { kubeapi.get_resource("configmaps", @spec_name) }.to raise_error(Kubeclient::ResourceNotFoundError)

        resource = Kubeclient::Resource.new(apiVersion: "v1", kind: "ConfigMap", metadata: {name: @spec_name}, data: {bar: "baz"})
        kubeapi.apply_resource(resource)

        fetched_resource = kubeapi.get_resource("configmaps", @spec_name)
        expect(fetched_resource.metadata.name).to eq(@spec_name)
        expect(fetched_resource.metadata.labels.to_h).to match(hash_including(KubeApi::MANAGED_LABEL_KEY.to_sym => KubeApi::MANAGED_LABEL_VALUE))
      end

      it "creates other types of resources" do
        expect { kubeapi.get_resource("secrets", @spec_name) }.to raise_error(Kubeclient::ResourceNotFoundError)

        resource = Kubeclient::Resource.new(apiVersion: "v1", kind: "Secret", metadata: {name: @spec_name}, data: {bar: Base64.strict_encode64("baz")})
        kubeapi.apply_resource(resource)

        fetched_resource = kubeapi.get_resource("secrets", @spec_name)
        expect(fetched_resource.kind).to eq("Secret")
        expect(fetched_resource.metadata.namespace).to eq(kubeapi.namespace)
        expect(fetched_resource.metadata.name).to eq(@spec_name)
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
