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

  end
end