require 'rspec'
require 'kubetruth/kubeapi'

module Kubetruth
  describe KubeApi, :vcr do

    def namespace; "kubetruth-test-ns"; end
    def helm_name; "kubetruth-test-app"; end

    if ! ENV['CI']
      def teardown
        sysrun("helm delete --namespace #{namespace} #{helm_name}", output_on_fail: false, allow_fail: true)
        sysrun("kubectl --context docker-desktop delete namespace #{namespace}", output_on_fail: false, allow_fail: true)
      end

      def setup
        teardown
        root = File.expand_path('../..', __dir__)
        sysrun("helm install --create-namespace --namespace #{namespace} --set appSettings.apiKey=#{ENV['CT_API_KEY']} #{helm_name} #{root}/helm/kubetruth/")
      end

      def token
        @token ||= begin
          secret_names = sysrun("kubectl --context docker-desktop --namespace #{namespace} get secret").lines
          secret_names = secret_names.grep(/#{helm_name}-token/)
          secret_name = secret_names.first.split.first
          token_lines = sysrun("kubectl --context docker-desktop --namespace #{namespace} describe secret #{secret_name}").lines
          token_lines = token_lines.grep(/token:/)
          token_lines.first.split[1]
        end
      end

      before(:all) do
        setup
      end

      after(:all) do
        teardown
      end
    else
      def token; ""; end
    end

    let(:kubeapi) { described_class.new(namespace: namespace, token: token, api_url: "https://kubernetes.docker.internal:6443") }

    describe "configmaps" do

      it "can crud config maps" do
        expect { kubeapi.get_config_map("foo") }.to raise_error(Kubeclient::ResourceNotFoundError)
        cm = kubeapi.create_config_map("foo", {bar: "baz"})
        expect(kubeapi.get_config_map_names).to include("foo")
        expect(kubeapi.get_config_map("foo")).to eq({bar: "baz"})
        kubeapi.update_config_map("foo", {bar: "bum"})
        expect(kubeapi.get_config_map("foo")).to eq({bar: "bum"})
        kubeapi.delete_config_map("foo")
        expect { kubeapi.get_config_map("foo") }.to raise_error(Kubeclient::ResourceNotFoundError)
      end

    end

    describe "secrets" do

      it "can crud secrets" do
        expect { kubeapi.get_secret("foo") }.to raise_error(Kubeclient::ResourceNotFoundError)
        secret = kubeapi.create_secret("foo", {bar: "baz"})
        expect(kubeapi.get_secret_names).to include("foo")
        expect(kubeapi.get_secret("foo")).to eq({bar: "baz"})
        kubeapi.update_secret("foo", {bar: "bum"})
        expect(kubeapi.get_secret("foo")).to eq({bar: "bum"})
        kubeapi.delete_secret("foo")
        expect { kubeapi.get_secret("foo") }.to raise_error(Kubeclient::ResourceNotFoundError)
      end

    end

  end
end
