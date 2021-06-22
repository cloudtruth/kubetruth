require 'rspec'
require 'kubetruth/cli_liquid_tester'

module Kubetruth
  describe CLILiquidTester do

    let(:cli) { described_class.new("") }

    describe "--help" do

      it "produces help text under standard width" do
        all_usage(described_class).each do |m|
          expect(m[:usage]).to be_line_width_for_cli(m[:name])
        end
      end

    end

    describe "version" do

      it "uses flag to produce version text" do
        expect { cli.run(['--version']) }.to raise_error(SystemExit)
        expect(Logging.contents).to include(VERSION)
      end

    end

    describe "--debug" do

      it "defaults to info log level" do
        expect(Logging).to receive(:setup_logging).with(hash_including(level: :info))
        expect { cli.run(['--version']) }.to raise_error(SystemExit)
      end

      it "sets log level to debug" do
        expect(Logging).to receive(:setup_logging).with(hash_including(level: :debug))
        expect { cli.run(['--debug', '--version']) }.to raise_error(SystemExit)
      end

    end

    describe "--quiet" do

      it "defaults to info log level" do
        expect(Logging).to receive(:setup_logging).with(hash_including(level: :info))
        expect { cli.run(['--version']) }.to raise_error(SystemExit)
      end

      it "sets log level to warn" do
        expect(Logging).to receive(:setup_logging).with(hash_including(level: :error))
        expect { cli.run(['--quiet', '--version']) }.to raise_error(SystemExit)
      end

    end

    describe "--no-color" do

      it "defaults to color" do
        expect(Logging).to receive(:setup_logging).with(hash_including(color: true))
        expect { cli.run(['--version']) }.to raise_error(SystemExit)
      end

      it "outputs plain text" do
        expect(Logging).to receive(:setup_logging).with(hash_including(color: false))
        expect { cli.run(['--no-color', '--version']) }.to raise_error(SystemExit)
      end

    end

    describe "no args" do

      it "fails for no templates" do
        expect { cli.run([]) }.to raise_error(Clamp::UsageError, /No template supplied/)
      end

    end

    describe "--template" do

      it "uses supplied template" do
        expect { cli.run(['--template', 'foo']) }.to output("foo\n").to_stdout
      end

    end

    describe "--template-file" do

      it "uses supplied template" do
        expect { cli.run(['--template-file', File.expand_path("../fixtures/simple.tmpl", __dir__)]) }.to output("foo\n").to_stdout
      end

      it "uses stdin" do
        simulate_stdin("foo") do
          expect { cli.run(['--template-file', '-']) }.to output( "foo\n").to_stdout
        end
      end

    end

    describe "--variable" do

      it "uses supplied variables" do
        expect { cli.run(%w[--variable one=two --variable three=four --template {{one}}{{three}}]) }.to output("twofour\n").to_stdout
      end

      it "supplied variables can be structured" do
        expect { cli.run(%w(--variable one=[x,y] --template {{one\ |\ join:\ "-"}})) }.to output("x-y\n").to_stdout
      end

    end

  end
end
