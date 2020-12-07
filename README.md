[![Build Status](https://github.com/cloudtruth/kubetruth/workflows/CD/badge.svg)](https://github.com/cloudtruth/kubetruth/actions)
[![Coverage Status](https://coveralls.io/repos/github/cloudtruth/kubetruth/badge.svg?branch=master)](https://coveralls.io/github/cloudtruth/kubetruth?branch=master)

# Kubetruth

The CloudTruth integration for kubernetes that pushes parameter updates into
kubernetes config maps and secrets.  The goal is to provide you a mechanism that
is as hands off as possible, using naming conventions to automate the delivery
of configuration so that you don't have to jump through setup hoops for each
app/service/etc that you would like to configure with cloudtruth

## Installation

```shell
helm repo add cloudtruth https://packages.cloudtruth.com/charts/
helm install \
    --set appSettings.apiKey=<api_key> \
    --set appSettings.environment=<environment> \
    --set appSettings.keyPrefix=service \
    my-kubetruth-name cloudtruth/kubetruth
```

## Uninstall

```shell
helm delete my-kubetruth-name
helm repo remove cloudtruth
```

## Usage

Parameterize the helm install with `--set appSettings.**` to control how kubetruth matches against your organization's naming conventions:

| Parameter | Description | Type | Default | Required |
|-----------|-------------|------|---------|:--------:|
| appSettings.apiKey | The cloudtruth api key.  Read only access is sufficient | string | n/a | yes |
| appSettings.environment | The cloudtruth environment to lookup parameter values for.  Use a separate helm install for each environment | string | `default` | yes |
| appSettings.keyPrefix | Limit the parameters looked up to one of these prefixes | list(string) | n/a | no |
| appSettings.keyPattern | The pattern to match against key names to select params and provide keywords for generating resource names via nameTemplate and keyTemplate | list(regex) | `^(?<prefix>[^\.]+)\.(?<name>[^\.]+)\.(?<key>.*)` | no |
| appSettings.nameTemplate | The template for generating resources (ConfigMaps and Secrets) | string | `%{name}` | no |
| appSettings.keyTemplate | The template for generating key names within a resource | string | `%{key}` | no |
| appSettings.skipSecrets | Do not transfer parameters that are marked as secret | flag | false | no |
| appSettings.secretsAsConfig | Place secret parameters alongside plain parameters within a ConfigMap instead of in their own Secret resource | flag | false | no |
| appSettings.pollingInterval | Interval to poll cloudtruth api for changes | integer | 300 | no |
| appSettings.debug | Debug logging | flag | n/a | no |

For example, for a keyspace that looks like:
```
service.someServiceName.oneParam=value1
service.someServiceName.twoParam=value2
service.otherServiceName.someParam=val1
service.otherServiceName.mySecret=val2 (marked as a secret within CloudTruth)
```

and parameterization like:
```
    --set appSettings.keyPrefix=service \
    --set appSettings.keyPattern=^(?<prefix>[^\.]+)\.(?<name>[^\.]+)\.(?<key>.*) \
    --set appSettings.namePattern=%{name} \
    --set appSettings.keyPattern=ACME_%{key_upcase} \
```

Kubetruth will generate the config maps:

someServiceName:
```yaml
    ACME_ONEPARAM: value1
    ACME_TWOPARAM: value2
```

otherServiceName:
```yaml
    ACME_SOMEPARAM: val1
```

and the Secrets:

otherServiceName:
```yaml
    MYSECRET: val2
```

These kubernetes resources can then be referenced in the standard ways, e.g.

```yaml
    envFrom:
      - configMapRef:
          name: otherServiceName
    envFrom:
      - secretRef:
          name: otherServiceName
```

Note that config map updates don't get seen by a running pod.  You can use
something like [Reloader](https://github.com/stakater/Reloader) to automate
this, or read config from mounted volumes for configmaps/secrets, which do get
updated automatically in a running pod

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `bundle exec rspec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/cloudtruth/kubetruth.

