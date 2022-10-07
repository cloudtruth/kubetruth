require 'rspec'
require 'kubetruth/project_collection'
require 'kubetruth/config'

module Kubetruth
  describe ProjectCollection do

    let(:collection) { described_class.new(Kubetruth::Config::ProjectSpec.new) }

    before(:each) do
      @ctapi = double(Kubetruth::CtApi)
      allow(Kubetruth::CtApi).to receive(:new).and_return(@ctapi)
    end

    describe "#names" do

      it "gets project names from ctapi" do
        expect(@ctapi).to receive(:project_names).and_return(["proj1", "proj2"])
        expect(collection.names).to eq(["proj1", "proj2"])
      end

    end

    describe "#projects" do

      it "returns all projects created via create" do
        projects = {}
        projects["proj1"] = collection.create_project(name: "proj1", spec: Kubetruth::Config::ProjectSpec.new)
        projects["proj2"] = collection.create_project(name: "proj2", spec: Kubetruth::Config::ProjectSpec.new)
        expect(collection.projects).to eq(projects)
      end

    end

    describe "#create" do

      it "creates a project and adds to all" do
        spec = Kubetruth::Config::ProjectSpec.new
        proj = collection.create_project(name: "proj1", spec: spec)
        expect(proj).to be_an_instance_of(Project)
        expect(proj.name).to eq("proj1")
        expect(proj.spec).to eq(spec)
        expect(collection.projects).to eq({"proj1" => proj})
      end

    end

  end
end
