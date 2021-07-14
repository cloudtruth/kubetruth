require 'rspec'
require 'async'
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

    describe "instance" do

      it "fails if not configured" do
        expect { described_class.instance }.to raise_error(ArgumentError, /has not been configured/)
      end

      it "succeeds when configured" do
        described_class.configure(namespace: "ns1", token: "token1", api_url: "http://localhost")
        expect(described_class.instance).to be_an_instance_of(described_class)
        expect(described_class.instance).to equal(described_class.instance)
        expect(described_class.instance.instance_variable_get(:@namespace)).to eq("ns1")
        expect(described_class.instance.instance_variable_get(:@auth_options)).to eq({bearer_token: "token1"})
        expect(described_class.instance.instance_variable_get(:@api_url)).to eq("http://localhost")
      end

    end

    describe "initialize" do

      it "uses supplied namespace" do
        expect(described_class.new(namespace: "foo").namespace).to eq("foo")
      end

      it "adds options when running in kube" do
        expect(File).to receive(:read).with(KubeApi::NAMESPACE_PATH).and_return("foo\n")
        expect(File).to receive(:exist?).with(KubeApi::TOKEN_PATH).and_return(true)
        expect(File).to receive(:exist?).with(KubeApi::CA_PATH).and_return(true)
        instance = described_class.new
        expect(instance.namespace).to eq("foo")
        expect(instance.instance_variable_get(:@auth_options)[:bearer_token_file]).to eq(KubeApi::TOKEN_PATH)
        expect(instance.instance_variable_get(:@ssl_options)[:ca_file]).to eq(KubeApi::CA_PATH)
      end

    end

    describe "#api_url" do

      it "generates api url" do
        base_api_url = kubeapi.instance_variable_get(:@api_url)
        expect(kubeapi.api_url(nil)).to eq(base_api_url)
        expect(kubeapi.api_url("")).to eq(base_api_url)
        expect(kubeapi.api_url("   ")).to eq(base_api_url)
        expect(kubeapi.api_url("kubetruth.cloudtruth.com")).to eq("#{base_api_url}/apis/kubetruth.cloudtruth.com")
      end

    end

    describe "#api_client" do

      it "generates api client" do
        expect(kubeapi.instance_variable_get(:@api_clients)).to eq({})

        client = kubeapi.api_client(api: nil)
        expect(client).to be_an_instance_of(Kubeclient::Client)
        expect(kubeapi.instance_variable_get(:@api_clients).size).to eq(1)
      end

      it "memoizes api client" do
        expect(kubeapi.api_client(api: nil)).to equal(kubeapi.api_client(api: nil))
        expect(kubeapi.instance_variable_get(:@api_clients).size).to eq(1)
      end

      it "generates multiple api clients for differing apis" do
        expect(kubeapi.instance_variable_get(:@api_clients)).to eq({})

        expect(kubeapi.api_client(api: nil)).to_not equal(kubeapi.api_client(api: "kubetruth.cloudtruth.com"))
        expect(kubeapi.instance_variable_get(:@api_clients).size).to eq(2)
      end

      it "generates multiple api clients for differing versions" do
        expect(kubeapi.instance_variable_get(:@api_clients)).to eq({})

        expect(kubeapi.api_client(api: nil)).to_not equal(kubeapi.api_client(api: nil, version: "v2"))
        expect(kubeapi.instance_variable_get(:@api_clients).size).to eq(2)
      end

    end

    describe "#client" do

      it "generates kube client" do
        expect(kubeapi.instance_variable_get(:@api_clients)).to eq({})

        expect(kubeapi.client).to be_an_instance_of(Kubeclient::Client)
        expect(kubeapi.client).to equal(kubeapi.client)
        expect(kubeapi.client.api_endpoint.path).to eq("/api")
      end

    end

    describe "#crd_client" do

      it "generates crd client" do
        expect(kubeapi.instance_variable_get(:@api_clients)).to eq({})

        expect(kubeapi.crd_client).to be_an_instance_of(Kubeclient::Client)
        expect(kubeapi.crd_client).to equal(kubeapi.crd_client)
        expect(kubeapi.crd_client.api_endpoint.path).to eq("/apis/kubetruth.cloudtruth.com")
      end

    end

    describe "#apiVersion_client" do

      it "generates client" do
        expect(kubeapi.instance_variable_get(:@api_clients)).to eq({})
        apiVersion = "kubetruth.cloudtruth.com/v1"
        expect(kubeapi.apiVersion_client(apiVersion)).to be_an_instance_of(Kubeclient::Client)
        expect(kubeapi.apiVersion_client(apiVersion)).to equal(kubeapi.apiVersion_client(apiVersion))
        expect(kubeapi.apiVersion_client(apiVersion).api_endpoint.path).to eq("/apis/kubetruth.cloudtruth.com")
      end

      it "generates client without version" do
        expect(kubeapi.apiVersion_client("v1")).to equal(kubeapi.apiVersion_client(nil))
      end

      it "handles empty apiVersion" do
        expect(kubeapi.instance_variable_get(:@api_clients)).to eq({})
        apiVersion = nil
        expect(kubeapi.apiVersion_client(apiVersion)).to be_an_instance_of(Kubeclient::Client)
        expect(kubeapi.apiVersion_client(apiVersion)).to equal(kubeapi.apiVersion_client(apiVersion))
        expect(kubeapi.apiVersion_client(apiVersion).api_endpoint.path).to eq("/api")
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

        newns = "#{namespace}-newns2"
        expect { kapi.client.get_namespace(newns) }.to raise_error(Kubeclient::ResourceNotFoundError, /namespaces.*not found/)
        kapi.ensure_namespace(newns)
        ns = kapi.client.get_namespace(newns)
        expect(ns.kind).to eq("Namespace")
        expect(ns.metadata.name).to eq(newns)
      end

      it "sets labels when creating namespace" do
        kapi = described_class.new(namespace: "#{namespace}-newns3", token: token, api_url: apiserver)
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

      it "gets api resource" do
        pm_name = "#{helm_name}-root"
        fetched_resource = kubeapi.get_resource("projectmappings", pm_name, apiVersion: "kubetruth.cloudtruth.com/v1")
        expect(fetched_resource.metadata.name).to eq(pm_name)
      end

    end

    describe "apply_resource" do

      it "creates a resource" do
        kapi = described_class.new(namespace: "#{namespace}-arns", token: token, api_url: apiserver)
        kapi.ensure_namespace
        ns = kapi.namespace

        expect { kubeapi.get_resource("configmaps", @spec_name, namespace: ns) }.to raise_error(Kubeclient::ResourceNotFoundError)

        resource = Kubeclient::Resource.new(apiVersion: "v1", kind: "ConfigMap", metadata: {namespace: ns, name: @spec_name}, data: {bar: "baz"})
        kubeapi.apply_resource(resource)

        fetched_resource = kubeapi.get_resource("configmaps", @spec_name, namespace: ns)
        expect(fetched_resource.metadata.namespace).to eq(ns)
        expect(fetched_resource.metadata.name).to eq(@spec_name)
      end

      it "creates a resource from hash" do
        expect { kubeapi.get_resource("configmaps", @spec_name) }.to raise_error(Kubeclient::ResourceNotFoundError)

        resource = { apiVersion: "v1", kind: "ConfigMap", metadata: { namespace: kubeapi.namespace, name: @spec_name }, data: { bar: "baz" } }
        kubeapi.apply_resource(resource)

        fetched_resource = kubeapi.get_resource("configmaps", @spec_name)
        expect(fetched_resource.metadata.namespace).to eq(kubeapi.namespace)
        expect(fetched_resource.metadata.name).to eq(@spec_name)
        expect(fetched_resource.data.to_h).to eq({bar: "baz"})
      end

      it "creates other types of resources" do
        expect { kubeapi.get_resource("secrets", @spec_name) }.to raise_error(Kubeclient::ResourceNotFoundError)

        resource = Kubeclient::Resource.new(apiVersion: "v1", kind: "Secret", metadata: {namespace: kubeapi.namespace, name: @spec_name}, data: {bar: Base64.strict_encode64("baz")})
        kubeapi.apply_resource(resource)

        fetched_resource = kubeapi.get_resource("secrets", @spec_name)
        expect(fetched_resource.kind).to eq("Secret")
        expect(fetched_resource.metadata.namespace).to eq(kubeapi.namespace)
        expect(fetched_resource.metadata.name).to eq(@spec_name)
      end

      it "creates resources in other apis" do
        pm_name = "#{helm_name}-override"
        api = "kubetruth.cloudtruth.com/v1"

        expect { kubeapi.get_resource("projectmappings", pm_name, apiVersion: api) }.to raise_error(Kubeclient::ResourceNotFoundError)

        resource = Kubeclient::Resource.new(apiVersion: api, kind: "ProjectMapping", metadata: {namespace: kubeapi.namespace, name: pm_name}, spec: {skip: true})
        kubeapi.apply_resource(resource)

        fetched_resource = kubeapi.get_resource("projectmappings", pm_name, apiVersion: api)
        expect(fetched_resource.apiVersion).to eq(api)
        expect(fetched_resource.kind).to eq("ProjectMapping")
        expect(fetched_resource.metadata.namespace).to eq(kubeapi.namespace)
        expect(fetched_resource.metadata.name).to eq(pm_name)
      end

    end

    describe "custom resource" do

      it "can get project mappings" do
        crds = kubeapi.get_project_mappings
        expect(crds.size).to eq(1) # from helm install
        # {namespace => {name => mapping_data}}
        expect(crds.keys.first).to eq(kubeapi.namespace)
        expect(crds.values.first).to match(hash_including("#{helm_name}-root"))
        expect(crds.values.first["#{helm_name}-root"][:name]).to eq("#{helm_name}-root")
        expect(crds.values.first["#{helm_name}-root"].keys.sort).to eq(Kubetruth::Config::ProjectSpec.new.to_h.keys.sort)
      end

      it "can watch project mappings" do
        existing_ver = kubeapi.crd_client.get_project_mappings.resourceVersion
        block = Proc.new {}
        expect(kubeapi.crd_client).to receive(:watch_project_mappings).with(resource_version: existing_ver, &block)
        kubeapi.watch_project_mappings(&block)
      end

    end

    describe "validate async" do

      it "does api requests concurrently" do
        kapi = kubeapi # rspec let block has a mutex that intermittently causes problems when using async
        start_times = {}
        end_times = {}
        start_times[:total] = Time.now.to_f


          Async(annotation: "top") do

            Async(annotation: "first") do
              start_times[:first] = Time.now.to_f
              kapi.get_project_mappings # non-memoized
              end_times[:first] = Time.now.to_f
            end

            Async(annotation: "second") do
              begin
                start_times[:second] = Time.now.to_f
                kapi.get_project_mappings # non-memoized
                end_times[:second] = Time.now.to_f
              rescue => e
                puts e
                puts e.backtrace
              end
            end

          end

        end_times[:total] = Time.now.to_f
        elapsed_times = Hash[end_times.collect {|k, v| [k, v - start_times[k]]}]

        logger.debug { "Start times: #{start_times.inspect}" }
        logger.debug { "End times: #{end_times.inspect}" }
        logger.debug { "Elapsed times: #{elapsed_times.inspect}" }

        # When VCR plays back requests, it doesn't use concurrent IO like live
        # requests do, so this assertion will fail.  As a result we only do the
        # check when someone has cleared the cassette and is re-running against
        # an actual http api
        if VCR.current_cassette.originally_recorded_at.nil? || VCR.current_cassette.record_mode == :all
          expect(elapsed_times[:total]).to be < (elapsed_times[:first] + elapsed_times[:second])
        end
      end

    end

  end
end
