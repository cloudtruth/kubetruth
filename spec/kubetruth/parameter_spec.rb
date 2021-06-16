require 'rspec'
require 'kubetruth/parameter'

module Kubetruth
  describe Parameter do

    describe "#initialize" do

      it "creates from kwargs" do
        data = {key: "key1", value: "value1", secret: true}
        param = described_class.new(**data)
        expect(param.to_h).to eq(data)
      end

    end

  end
end
