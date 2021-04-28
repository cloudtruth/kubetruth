require 'rspec'
require 'kubetruth/ctapi'


module Kubetruth

  describe "CtApi", :vcr do

    let(:ctapi) { ::Kubetruth::CtApi(api_key: ENV['CT_API_KEY']) }

    describe "class definition", :vcr do

      it "defines class with key/schema" do
        expect(ctapi.client).to_not be_nil
        instance = ctapi.new()
        expect(instance.environment).to eq("default")
      end

    end

    describe "#organizations" do

      it "gets organizations" do
        api = ctapi.new
        expect(api.organizations).to match hash_including("CloudTruth Demo")
        expect(api.organization_names).to match array_including("CloudTruth Demo")
      end

    end

    describe "#environments" do

      it "gets environments" do
        api = ctapi.new
        expect(api).to_not receive(:organizations)
        expect(api.environments).to match hash_including("default")
        expect(api.environment_names).to match array_including("default")
      end

      it "uses organization to get environments" do
        api = ctapi.new(organization: "CloudTruth Demo")
        expect(api).to receive(:organizations).and_call_original
        allow(ctapi.client).to receive(:query).and_call_original
        expect(ctapi::client).to receive(:query).
            with(ctapi.queries[:EnvironmentsQuery],
                 variables: hash_including(:organizationId)).and_call_original
        expect(api.environments).to match hash_including("default")
        expect(api.environment_names).to match array_including("default")
      end

    end

    describe "#projects" do

      it "gets projects" do
        api = ctapi.new
        expect(api).to_not receive(:organizations)
        expect(api.projects).to match hash_including("default")
        expect(api.project_names).to match array_including("default")
      end

      it "doesn't cache projects " do
        api = ctapi.new
        expect(api.projects).to_not equal(api.projects)
        expect(api.project_names).to_not equal(api.project_names)
      end

      it "uses organization to get projects" do
        api = ctapi.new(organization: "CloudTruth Demo")
        expect(api).to receive(:organizations).and_call_original
        allow(ctapi.client).to receive(:query).and_call_original
        expect(ctapi::client).to receive(:query).
          with(ctapi.queries[:ProjectsQuery],
               variables: hash_including(:organizationId)).and_call_original
        expect(api.projects).to match hash_including("default")
      end

    end

    describe "#parameters" do

      it "gets parameters without a search" do
        api = ctapi.new
        expect(api).to_not receive(:organizations)
        expect(api.parameters).to match array_including(Parameter)
      end

      it "doesn't expose secret in debug log" do
        api = ctapi.new
        params = api.parameters
        secrets = params.find {|p| p.secret }
        expect(secrets.size).to_not eq(0)
        expect(Logging.contents).to include("<masked>")
      end

      it "uses organization to get values" do
        api = ctapi.new(organization: "CloudTruth Demo")
        expect(api).to receive(:organizations).at_least(:once).and_call_original
        allow(ctapi.client).to receive(:query).and_call_original
        expect(ctapi.client).to receive(:query).
            with(ctapi.queries[:ParametersQuery],
                 variables: hash_including(:organizationId)).and_call_original
        expect(api.parameters).to match array_including(Parameter)
      end

      it "uses project to get values" do
        api = ctapi.new
        expect(api).to_not receive(:organizations)
        expect(api.parameters(project: "default")).to match array_including(Parameter)
      end

      it "uses environment to get values" do
        api = ctapi.new(environment: "development")
        dev_id = api.environments["development"]
        allow(ctapi.client).to receive(:query).and_call_original
        expect(ctapi.client).to receive(:query).
            with(ctapi.queries[:ParametersQuery],
                 variables: hash_including(:environmentId => dev_id)).and_call_original
        expect(api.parameters).to match array_including(Parameter)
      end

      it "uses searchTerm to get parameters" do
        api = ctapi.new

        all = api.parameters
        expect(all.size).to be > 0

        expect(api.parameters(searchTerm: "nothingtoseehere")).to eq([])

        some = api.parameters(searchTerm: "services")
        expect(some.size).to be > 0
        expect(some.size).to be < all.size
        some.each {|p| expect(p.key).to include("services") }
      end

    end

  end

end
