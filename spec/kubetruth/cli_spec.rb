require 'rspec'
require 'kubetruth/cli'

module Kubetruth
  describe CLI do

    let(:cli) { described_class.new("") }

    describe "--help" do

      it "produces help text under standard width" do
        all_usage(described_class).each do |m|
          expect(m[:usage]).to be_line_width_for_cli(m[:name])
        end
      end

    end

    describe "execute" do

      it "passes args to etl" do
        args = %w[
            --api-key abc123
            --api-url cu
            --kube-namespace kn
            --kube-token kt
            --kube-url ku
            --dry-run
            --no-async
            --polling-interval 27
        ]

        expect(Kubetruth::CtApi).to receive(:configure).with({
                                                               api_key: "abc123",
                                                               api_url: "cu"
                                                             })

        expect(Kubetruth::KubeApi).to receive(:configure).with({
                                                                 namespace: "kn",
                                                                 token: "kt",
                                                                 api_url: "ku"
                                                             })

        etl = double(ETL)
        expect(ETL).to receive(:new).with(dry_run: true, async: false).and_return(etl)
        expect(etl).to receive(:apply)
        expect(etl).to receive(:with_polling).with(27).and_yield
        cli.run(args)
      end

      it "wakes up on signal" do
        expect {
          pid = Process.fork do
            $stdout.sync = $stderr.sync = true
            Kubetruth::Logging.testing = false
            Kubetruth::Logging.setup_logging(level: :debug, color: false)

            allow(Kubetruth::CtApi).to receive(:instance).and_return(double(Kubetruth::CtApi))
            allow(Kubetruth::KubeApi).to receive(:instance).and_return(double(Kubetruth::KubeApi))

            etl = ETL.new(dry_run: true)
            allow(ETL).to receive(:new).and_return(etl)

            watcher = double("watcher")
            allow(watcher).to receive(:each)
            allow(watcher).to receive(:finish)
            allow(etl.kubeapi).to receive(:watch_project_mappings).and_return(watcher)

            count = 0
            allow(etl).to receive(:apply) do
              puts "FakeApply #{count}"
              count += 1
              exit if count > 1
            end
            cli.run(%w[--api-key xyz --kube-namespace ns1 --kube-token xyz --polling-interval 1])
          end
          sleep 0.5
          Process.kill("HUP", pid)
          Process.wait(pid)
        }.to output(/FakeApply 0.*Poller sleeping.*Handling HUP signal.*FakeApply 1/m).to_stdout_from_any_process

      end

    end

  end
end
