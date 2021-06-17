require 'rspec'
require 'kubetruth/template'

module Kubetruth
  describe Template do

    describe "#to_s" do

      it "shows the template source" do
        expect(Template.new("foo").to_s).to eq("foo")
      end

    end

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

      describe "#key_safe" do

        it "returns if already valid" do
          str = "aB1-_."
          expect(key_safe(str)).to equal(str)
        end

        it "cleans up name" do
          expect(key_safe("Foo/Bar.Baz-0")).to eq("Foo_Bar.Baz-0")
        end

        it "simplifies successive non-chars" do
          expect(key_safe("foo/&!bar")).to eq("foo_bar")
        end

      end

      describe "#indent" do

        it "indents by count spaces for each line" do
          expect(indent("foo\nbar", 3)).to eq("   foo\n   bar")
        end

      end

      describe "#nindent" do

        it "indents by count spaces for each line with a leading newline" do
          expect(nindent("foo\nbar", 3)).to eq("   \n   foo\n   bar")
        end

      end

      describe "#stringify" do

        it "produces a yaml string" do
          expect(stringify("foo")).to eq('"foo"')
          expect(stringify(%q(foo'"bar))).to eq(%q("foo'\"bar"))
        end

      end

      describe "#to_yaml" do

        it "produces a yaml string" do
          expect(to_yaml([1, 2])).to eq("---\n- 1\n- 2\n")
        end

      end

      describe "#to_json" do

        it "produces a json string" do
          expect(to_json({"foo" => "bar"})).to eq('{"foo":"bar"}')
        end

      end

      describe "#sha256" do

        it "does a sha256 digest" do
          expect(sha256("foo")).to eq(Digest::SHA256.hexdigest("foo"))
        end

      end

      describe "#encode64" do

        it "does a base64 encode" do
          expect(encode64("foo")).to eq(Base64.strict_encode64("foo"))
        end

      end

      describe "#decode64" do

        it "does a base64 decode" do
          expect(decode64(Base64.strict_encode64("foo"))).to eq("foo")
        end

      end

    end

    describe "regexp match" do

      it "sets matchdata to nil for missing matches" do
        regex = /^(?<head>[^_]*)(_(?<tail>.*))?$/
        expect("foo_bar".match(regex).named_captures.symbolize_keys).to eq(head: "foo", tail: "bar")
        expect("foobar".match(regex).named_captures.symbolize_keys).to eq(head: "foobar", tail: nil)
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

      it "handles nil value in kwargs" do
        expect(described_class.new("hello {{foo}}").render(foo: nil)).to eq("hello ")
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
