require 'rspec'
require 'kubetruth/ctapi'


module Kubetruth

  describe "CtApi", :vcr do

    let(:ctapi) { ::Kubetruth::ctapi_setup(api_key: ENV['CLOUDTRUTH_API_KEY']); ::Kubetruth::CtApi }

    describe "class definition", :vcr do

      around(:each) do |ex|
        if defined? ::Kubetruth::CtApi
          oldconst = ::Kubetruth::CtApi
          ::Kubetruth.remove_const(:CtApi)
        end
        ex.run
        ::Kubetruth.const_set(:CtApi, oldconst) if oldconst
      end

      it "defines class" do
        expect(defined? ::Kubetruth::CtApi).to be_falsey
        ::Kubetruth.ctapi_setup(api_key: ENV['CLOUDTRUTH_API_KEY'])
        expect(defined? ::Kubetruth::CtApi).to be_truthy
        expect(::Kubetruth::CtApi).to be_a(Class)

        instance = ::Kubetruth::CtApi.new
        expect(instance).to be_an_instance_of(::Kubetruth::CtApi)
        instance.logger.debug "Hello"
        expect(Logging.contents).to match(/DEBUG\s*CtApi Hello/)
      end

    end

    describe "#environments" do

      it "gets environments" do
        api = ctapi.new
        expect(api.environments).to match hash_including("default")
        expect(api.environment_names).to match array_including("default")
      end

    end

    describe "#projects" do

      it "gets projects" do
        api = ctapi.new
        expect(api.projects).to match hash_including("default")
        expect(api.project_names).to match array_including("default")
      end

      it "doesn't cache projects " do
        api = ctapi.new
        expect(api.projects).to_not equal(api.projects)
        expect(api.project_names).to_not equal(api.project_names)
      end

    end

    describe "#parameters" do

      it "gets parameters without a search" do
        api = ctapi.new
        expect(api.parameters).to match array_including(Parameter)
      end

      it "doesn't expose secret in debug log" do
        api = ctapi.new
        params = api.parameters
        secrets = params.find {|p| p.secret }
        expect(secrets.size).to_not eq(0)
        expect(Logging.contents).to include("<masked>")
      end

      it "uses project to get values" do
        api = ctapi.new
        expect(api.parameters(project: "default")).to match array_including(Parameter)
      end

      it "uses environment to get values" do
        api = ctapi.new
        dev_id = api.environments["development"]
        allow(ctapi.client).to receive(:query).and_call_original
        expect(ctapi.client).to receive(:query).
            with(ctapi.queries[:ParametersQuery],
                 variables: hash_including(:environmentId => dev_id)).and_call_original
        expect(api.parameters(environment: "development")).to match array_including(Parameter)
      end

      it "uses searchTerm to get parameters" do
        api = ctapi.new

        all = api.parameters
        expect(all.size).to be > 0

        expect(api.parameters(searchTerm: "nothingtoseehere")).to eq([])

        some = api.parameters(searchTerm: "aParam")
        expect(some.size).to be > 0
        expect(some.size).to be < all.size
        some.each {|p| expect(p.key).to include("aParam") }
      end

    end

  end

end
