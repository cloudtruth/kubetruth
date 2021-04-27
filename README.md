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
| appSettings.pollingInterval | Interval to poll cloudtruth api for changes | integer | 300 | no |
| appSettings.debug | Debug logging | flag | n/a | no |

By default, Kubetruth maps the parameters from CloudTruth Projects into ConfigMaps and Secrets of the same names as the Projects. 

For example, for a CloudTruth layout that looks like:

`myProject`:
```
oneParam=value1
twoParam=value2
```

`otherProject`:
```
someParam=value3
mySecret=value4 (marked as a secret within CloudTruth)
```

Kubetruth will generate the kubernetes resources:

ConfigMap named `myProject`:
```yaml
    oneParam: value1
    twoParam: value2
```

ConfigMap named `otherProject`:
```yaml
    someParam: value3
```

Secret named `otherProject`:
```yaml
    mySecret: val2
```

These kubernetes resources can then be referenced in the standard ways.

To use them as environment variables in a pod:
```yaml
    envFrom:
      - configMapRef:
          name: otherProject
    envFrom:
      - secretRef:
          name: otherProject
```

To use them as files on disk in a pod:
```yaml
      containers:
        - name: myProject
          volumeMounts:
            - name: config-volume
              mountPath: /etc/myConfig
      volumes:
        - name: config-volume
          configMap:
            name: myProject
```

Note that config map updates don't get seen by a running pod.  You can use
something like [Reloader](https://github.com/stakater/Reloader) to automate
this, or read config from mounted volumes for configmaps/secrets, which do get
updated automatically in a running pod.

## Additional configuration

The kubetruth ConfigMap contains a [yaml file for additional config](helm/kubetruth/templates/configmap.yaml)

### Example Config

To create the kubernetes Resources in namespaces named after each Project:
```yaml
namespace_template: %{project}
```

To include the parameters from a Project named `Base` into all other projects, without creating Resources for `Base` itself:
```yaml
included_projects:
  - Base
project_overrides:
  - project_selector: Base
    skip: true
```

To override the naming of kubernetes Resources on a per-Project basis:
```yaml
project_overrides:
  - project_selector: funkyProject
    configmap_name_template: notSoFunkyConfigMap
    secret_name_template: notSoFunkySecret
    namespace_template: notSoFunkyNsmespace
```

To limit the Projects processed to those whose names start with `service`, except for `serviceOddball`:
```yaml
project_selector: ^service
project_overrides:
  - project_selector: serviceOddball
    skip: true
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `bundle exec rspec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install and run via helm in a local cluster:
``` 
docker build -t kubetruth . && helm install \
    --set image.repository=kubetruth --set image.pullPolicy=Never --set image.tag=latest \
    --set appSettings.debug=true --set appSettings.apiKey=$CT_API_KEY --set appSettings.environment=development \
    kubetruth ./helm/kubetruth/
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/cloudtruth/kubetruth.
