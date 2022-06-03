require_relative 'cli_base'
require_relative 'ctapi'
require_relative 'kubeapi'
require_relative 'etl'

module Kubetruth
  class CLI < CLIBase

    banner <<~EOF
      Scans cloudtruth parameters for `name-pattern`, using the `name` match as
      the name of the kubernetes config_map/secrets resource to apply those
      values to
    EOF

    option "--api-key",
           'APIKEY', "The cloudtruth api key",
           environment_variable: 'CLOUDTRUTH_API_KEY',
           required: true

    option "--api-url",
           'APIURL', "The cloudtruth api endpoint",
           environment_variable: 'CLOUDTRUTH_API_URL',
           default: "https://api.cloudtruth.io"

    option "--kube-namespace",
           'NAMESPACE', "The kubernetes namespace. Defaults to runtime namespace when run in kube"

    option "--kube-token",
           'TOKEN', "The kubernetes token to use for api. Defaults to mounted when run in kube"

    option "--kube-url",
           'ENDPOINT', "The kubernetes api url. Defaults to internal api endpoint when run in kube"

    option "--polling-interval", "INTERVAL", "the polling interval", default: 300 do |a|
      Integer(a)
    end

    option ["-n", "--dry-run"],
           :flag, "Perform a dry run",
           default: false

    option ["-a", "--[no-]async"],
           :flag, "Run using async I/O (or not)",
           default: true

    # TODO: option to map template to configmap?

    def execute
      super

      Kubetruth::CtApi.configure(api_key: api_key, api_url: api_url)
      Kubetruth::KubeApi.configure(namespace: kube_namespace, token: kube_token, api_url: kube_url)

      etl = ETL.new(dry_run: dry_run?, async: async?)

      Signal.trap("HUP") do
        puts "Handling HUP signal - waking up ETL poller" # logger cant be called from trap
        etl.interrupt_sleep
      end

      etl.with_polling(polling_interval) do
        etl.apply
      end

    end

  end
end
