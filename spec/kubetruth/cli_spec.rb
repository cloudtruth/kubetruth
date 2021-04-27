require 'rspec'
require 'kubetruth/cli'

module Kubetruth
  describe CLI do

    let(:cli) { described_class.new("") }

    def all_usage(clazz, path=[])
      Enumerator.new do |y|
        obj = clazz.new("")
        path << clazz.name.split(":").last if path.empty?
        cmd_path = path.join(" -> ")
        y << {name: cmd_path, usage: obj.help}

        clazz.recognised_subcommands.each do |sc|
          sc_clazz = sc.subcommand_class
          sc_name = sc.names.first
          all_usage(sc_clazz, path + [sc_name]).each {|sy| y << sy}
        end
      end
    end

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


    describe "execute" do

      it "passes args to etl" do
        args = %w[
            --environment production
            --organization acme
            --api-key abc123
            --config-file file.yml
            --kube-namespace kn
            --kube-token kt
            --kube-url ku
            --dry-run
        ]
        etl = double(ETL)
        expect(ETL).to receive(:new).with(config_file: "file.yml",
                                          ct_context: {
                                              organization: "acme",
                                              environment: "production",
                                              api_key: "abc123"
                                          },
                                          kube_context: {
                                              namespace: "kn",
                                              token: "kt",
                                              api_url: "ku"
                                          }).and_return(etl)
        expect(etl).to receive(:apply).with(dry_run: true)
        cli.run(args)
      end

      it "polls at interval" do
        etl = double(ETL)
        expect(ETL).to receive(:new).and_return(etl)
        expect(etl).to receive(:apply)
        expect(cli).to receive(:sleep).with(27).and_raise(SystemExit)
        expect { cli.run(%w[--api-key abc123 --polling-interval 27]) }.to raise_error(SystemExit)
      end

    end

  end
end
