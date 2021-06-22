require 'rspec'
require 'kubetruth/cli_base'

module Kubetruth
  describe CLIBase do

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
        cli.run([])
      end

      it "sets log level to debug" do
        expect(Logging).to receive(:setup_logging).with(hash_including(level: :debug))
        cli.run(['--debug'])
      end

    end

    describe "--quiet" do

      it "defaults to info log level" do
        expect(Logging).to receive(:setup_logging).with(hash_including(level: :info))
        cli.run([])
      end

      it "sets log level to warn" do
        expect(Logging).to receive(:setup_logging).with(hash_including(level: :error))
        cli.run(['--quiet'])
      end

    end

    describe "--no-color" do

      it "defaults to color" do
        expect(Logging).to receive(:setup_logging).with(hash_including(color: true))
        cli.run([])
      end

      it "outputs plain text" do
        expect(Logging).to receive(:setup_logging).with(hash_including(color: false))
        cli.run(['--no-color'])
      end

    end

  end
end
