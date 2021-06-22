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
            --environment production
            --organization acme
            --api-key abc123
            --kube-namespace kn
            --kube-token kt
            --kube-url ku
            --dry-run
            --polling-interval 27
        ]

        expect(Project).to receive(:ctapi_context=).with({
          organization: "acme",
          environment: "production",
          api_key: "abc123"
        })

        etl = double(ETL)
        expect(ETL).to receive(:new).with(kube_context: {
                                              namespace: "kn",
                                              token: "kt",
                                              api_url: "ku"
                                          },
                                          dry_run: true).and_return(etl)
        expect(etl).to receive(:apply)
        expect(etl).to receive(:with_polling).with(27).and_yield
        cli.run(args)
      end

      it "wakes up on signal" do
        expect {
          pid = fork do
            $stdout.sync = $stderr.sync = true
            Kubetruth::Logging.testing = false
            Kubetruth::Logging.setup_logging(level: :debug, color: false)


            etl = ETL.new(kube_context: {namespace: 'ns', token: 'xyz'}, dry_run: true)
            allow(ETL).to receive(:new).and_return(etl)

            watcher = double("watcher")
            allow(watcher).to receive(:each)
            allow(watcher).to receive(:finish)
            allow(etl.kubeapi).to receive(:watch_project_mappings).and_return(watcher)

            count = 0
            allow(etl).to receive(:apply) do
              puts "FakeApply #{count}"
              count += 1
              exit! if count > 1
            end
            cli.run(%w[--api-key xyz --polling-interval 1])
          end
          sleep 0.5
          Process.kill("HUP", pid)
          Process.wait(pid)
        }.to output(/FakeApply 0.*Poller sleeping.*Handling HUP signal.*FakeApply 1/m).to_stdout_from_any_process

      end

    end

  end
end
