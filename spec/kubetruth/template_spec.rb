require 'rspec'
require 'kubetruth/template'

module Kubetruth
  describe Template do

    describe "CustomLiquidFilters" do

      include Kubetruth::Template::CustomLiquidFilters

      describe "#dns_safe" do

        it "returns if already valid" do
          str = "foo"
          expect(dns_safe(str)).to equal(str)
        end

        it "cleans up name" do
          expect(dns_safe("foo_bar")).to eq("foo-bar")
        end

        it "forces lower case" do
          expect(dns_safe("Foo_Bar")).to eq("foo-bar")
        end

        it "simplifies successive non-chars" do
          expect(dns_safe("foo_&!bar")).to eq("foo-bar")
        end

        it "strips leading/trailing non-chars" do
          expect(dns_safe("_foo!bar_")).to eq("foo-bar")
        end

      end

      describe "#env_safe" do

        it "returns if already valid" do
          str = "FOO"
          expect(env_safe(str)).to equal(str)
        end

        it "cleans up name" do
          expect(env_safe("foo-bar")).to eq("FOO_BAR")
        end

        it "forces upper case" do
          expect(env_safe("Foo")).to eq("FOO")
        end

        it "precedes leading digit with underscore" do
          expect(env_safe("9foo")).to eq("_9FOO")
        end

        it "simplifies successive non-chars" do
          expect(env_safe("foo-&!bar")).to eq("FOO_BAR")
        end

        it "preserves successive underscores" do
          expect(env_safe("__foo__bar__")).to eq("__FOO__BAR__")
        end

        it "strips leading/trailing non-chars" do
          expect(env_safe("-foo!bar-")).to eq("FOO_BAR")
        end

      end

    end

    describe "#render" do

      it "works with plain strings" do
        expect(described_class.new(nil).render).to eq("")
        expect(described_class.new("").render).to eq("")
        expect(described_class.new("foo").render).to eq("foo")
      end

      it "substitutes from kwargs" do
        expect(described_class.new("hello {{foo}}").render("foo" => "bar")).to eq("hello bar")
        expect(described_class.new("hello {{foo}}").render(foo: "bar")).to eq("hello bar")
      end


      it "has custom filters" do
        expect(described_class.new("hello {{foo | dns_safe}}").render(foo: "BAR")).to eq("hello bar")
        expect(described_class.new("hello {{foo | env_safe}}").render(foo: "bar")).to eq("hello BAR")
      end

      it "fails fast" do
        expect { described_class.new("{{foo") }.to raise_error(Kubetruth::Template::Error)
        expect { described_class.new("{{foo}}").render }.to raise_error(Kubetruth::Template::Error)
        expect { described_class.new("{{foo | nofilter}}").render(foo: "bar") }.to raise_error(Kubetruth::Template::Error)
      end

    end

  end
end
