require 'rspec'
require 'kubetruth/project'
require 'kubetruth/project_collection'
require 'kubetruth/parameter'
require 'kubetruth/config'

module Kubetruth
  describe Project do

    let(:collection) { ProjectCollection.new(Kubetruth::Config::ProjectSpec.new) }

    before(:each) do
      @ctapi = double()
      @collection_ctapi = double()
      allow_any_instance_of(described_class).to receive(:ctapi).and_return(@ctapi)
      allow(collection).to receive(:ctapi).and_return(@collection_ctapi)
    end

    describe "#initialize" do

      it "creates from kwargs" do
        data = {name: "name1", spec: Kubetruth::Config::ProjectSpec.new, collection: collection}
        proj = described_class.new(**data)
        expect(proj.to_h).to eq(data)
      end

    end

    describe "#parameters" do

      let(:project) { described_class.new(name: "proj1",
                                             spec: Kubetruth::Config::ProjectSpec.new(**Kubetruth::Config::DEFAULT_SPEC),
                                             collection: collection) }

      it "handles empty" do
        expect(@ctapi).to receive(:parameters).with(project: project.name).and_return([])
        params = project.parameters
        expect(params).to eq([])
      end

      it "uses spec versions se" do
        expect(@ctapi).to receive(:parameters).with(project: project.name).and_return([])
        params = project.parameters
        expect(params).to eq([])
      end

      it "uses simple key_selector" do
        project.spec.key_selector = /svc/
        expect(@ctapi).to receive(:parameters).with(project: project.name).and_return([
          Parameter.new(key: "svc.param1", value: "value1", secret: false),
          Parameter.new(key: "svc.param2", value: "value2", secret: false),
        ])
        params = project.parameters
        expect(params.size).to eq(2)
        expect(Logging.contents).to match(/Looking for key pattern matches/)
      end

      it "uses complex key_selector" do
        project.spec.key_selector = /foo$/
        expect(@ctapi).to receive(:parameters).with(project: project.name).and_return([
          Parameter.new(key: "svc.param1", value: "value1", secret: false),
          Parameter.new(key: "svc.param2.foo", value: "value2", secret: false),
        ])
        params = project.parameters
        expect(params.size).to eq(1)
        expect(params.collect(&:key)).to eq(["svc.param2.foo"])
        expect(Logging.contents).to match(/Looking for key pattern matches/)
      end

      it "doesn't expose secret in debug log" do
        Logging.setup_logging(level: :debug, color: false)

        expect(@ctapi).to receive(:parameters).with(project: project.name).and_return([
                                                              Parameter.new(key: "param1", value: "value1", secret: false),
                                                              Parameter.new(key: "param2", value: "sekret", secret: true),
                                                              Parameter.new(key: "param3", value: "alsosekret", secret: true),
                                                              Parameter.new(key: "param4", value: "value4", secret: false),
                                                          ])
        params = project.parameters
        expect(Logging.contents).to include("param2")
        expect(Logging.contents).to include("param3")
        expect(Logging.contents).to include("<masked>")
        expect(Logging.contents).to_not include("sekret")
      end

    end

    describe "tree traversal" do

      let(:config) {
        Kubetruth::Config.new([
                                Kubetruth::Config::DEFAULT_SPEC.merge(scope: "root"),
                                Kubetruth::Config::DEFAULT_SPEC.merge(project_selector: "proj1"),
                                Kubetruth::Config::DEFAULT_SPEC.merge(project_selector: "proj2"),
                                Kubetruth::Config::DEFAULT_SPEC.merge(project_selector: "proj3")
                              ])
      }
      let(:proj1) { collection.create_project(name: "proj1", spec: config.spec_for_project("proj1")) }
      let(:proj2) { collection.create_project(name: "proj2", spec: config.spec_for_project("proj2")) }
      let(:proj3) { collection.create_project(name: "proj3", spec: config.spec_for_project("proj3")) }

      before(:each) do
        # make sure they are loaded in Project.all
        all_projects = [proj1, proj2, proj3]
      end

      describe "#included_projects" do

        it "gets single level of included projects" do
          proj1.spec.included_projects = ["proj2", "proj3"]
          projects = proj1.included_projects
          expect(projects).to eq({proj2.name => {}, proj3.name => {}})
          expect(Logging.contents).to_not match(/Breaking circular dependency/)
          expect(Logging.contents).to_not match(/Skipping unknown project/)
        end

        it "gets multiple levels of included projects" do
          proj1.spec.included_projects = ["proj2", "proj3"]
          proj2.spec.included_projects = ["proj3"]
          projects = proj1.included_projects
          expect(projects).to eq({proj2.name => {proj3.name => {}}, proj3.name => {}})
        end

        it "breaks cycles to self" do
          proj1.spec.included_projects = ["proj1"]
          projects = proj1.included_projects
          expect(projects).to eq({})
          expect(Logging.contents).to match(/Breaking circular dependency/)
        end

        it "breaks nested cycles" do
          proj1.spec.included_projects = ["proj2"]
          proj2.spec.included_projects = ["proj3"]
          proj3.spec.included_projects = ["proj1"]
          projects = proj1.included_projects
          expect(projects).to eq({proj2.name => {proj3.name => {}}})
          expect(Logging.contents).to match(/Breaking circular dependency/)
        end

        it "skips unknown projects" do
          proj1.spec.included_projects = ["proj4"]
          projects = proj1.included_projects
          expect(projects).to eq({})
          expect(Logging.contents).to match(/Skipping unknown project/)
        end

        it "yields each project in a DFS fashion" do
          proj1.spec.included_projects = ["proj2", "proj3"]
          proj2.spec.included_projects = ["proj3"]

          expect { |b| proj1.included_projects(&b) }.
            to yield_successive_args(proj3, proj2, proj3)
        end

      end

      describe "#all_parameters" do

        it "gets parameters for included projects and self" do
          proj1.spec.included_projects = ["proj2"]
          proj2.spec.included_projects = ["proj3"]

          expect(proj1).to receive(:parameters).and_return([param1 = Parameter.new(key: "proj1key")])
          expect(proj2).to receive(:parameters).and_return([param2 = Parameter.new(key: "proj2key")])
          expect(proj3).to receive(:parameters).and_return([param3 = Parameter.new(key: "proj3key")])

          params = proj1.all_parameters
          expect(params).to eq([param3, param2, param1])
        end

      end

      describe "#parameter_origins" do

        it "enumerates parameter origins by project" do
          proj1.spec.included_projects = ["proj2"]
          proj2.spec.included_projects = ["proj3"]

          proj1_params = [
            Parameter.new(key: "param0", value: "proj1value0"),
            Parameter.new(key: "param2", value: "proj1value2"),
            Parameter.new(key: "param3", value: "proj1value3"),
          ]
          proj2_params = [
            Parameter.new(key: "param3", value: "proj2value3"),
            Parameter.new(key: "param4", value: "proj2value4"),
          ]
          proj3_params = [
            Parameter.new(key: "param1", value: "proj3value1"),
            Parameter.new(key: "param2", value: "proj3value2"),
            Parameter.new(key: "param3", value: "proj3value3"),
          ]

          expect(proj1).to receive(:parameters).and_return(proj1_params)
          expect(proj2).to receive(:parameters).and_return(proj2_params)
          expect(proj3).to receive(:parameters).and_return(proj3_params)


          expect(proj1.parameter_origins).to eq({
             "param0" => "proj1",
             "param1" => "proj3",
             "param2" => "proj1 (proj3)",
             "param3" => "proj1 (proj2 -> proj3)",
             "param4" => "proj2"
           })

        end

      end

      describe "#heirarchy" do

        it "gets heirarchy of included projects including self" do
          proj1.spec.included_projects = ["proj2", "proj3"]
          expect(proj1.heirarchy).to eq({
                                          proj1.name => {
                                            proj2.name => {},
                                            proj3.name => {}
                                          }
                                        })
        end

      end

    end

  end
end
