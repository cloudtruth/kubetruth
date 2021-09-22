require 'rspec'
require 'kubetruth/logging'

module Kubetruth
  describe Logging do

    let(:logger) { ::Logging.logger.root }

    describe "setup_logging" do

      it "logs at info log level" do
        described_class.setup_logging(level: :info, color: false)
        logger.info("infolog")
        expect(Logging.contents).to include("infolog")
        logger.debug("debuglog")
        expect(Logging.contents).to_not include("debuglog")
      end

      it "logs at debug log level" do
        described_class.setup_logging(level: :debug, color: false)
        logger.info("infolog")
        expect(Logging.contents).to include("infolog")
        logger.debug("debuglog")
        expect(Logging.contents).to include("debuglog")
      end

      it "logs with color" do
        described_class.setup_logging(level: :info, color: true)
        logger.info("howdy")
        a = ::Logging.logger.root.appenders.find {|a| a&.layout&.color_scheme }
        expect(a).to_not be_nil
      end

      it "outputs plain text" do
        described_class.setup_logging(level: :info, color: false)
        a = ::Logging.logger.root.appenders.find {|a| a&.layout&.color_scheme }
        expect(a).to be_nil
      end

    end

    describe "#root_log_level" do

      it "gets and sets root log level" do
        expect(described_class.root_log_level).to eq("debug")
        described_class.root_log_level = "error"
        expect(described_class.root_log_level).to eq("error")
      end

      it "logs at set log level" do
        described_class.root_log_level = "info"
        logger.info("infolog")
        expect(Logging.contents).to include("infolog")
        logger.debug("debuglog")
        expect(Logging.contents).to_not include("debuglog")
      end

    end

  end

end