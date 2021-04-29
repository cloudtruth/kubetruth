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

Kubetruth uses a CustomResourceDefinition called
[ProjectMapping(.kubetruth.cloudtruth.com)](helm/kubetruth/crds/projectmapping.yaml)
for additional configuration.  The ProjectMapping CRD has two types identified
by the `scope` property, the `root` scope and the `override` scope.  The `root`
scope is required, and there can be only one.  It sets up the global behavior
for mapping the CloudTruth projects to kubernetes resources.  You can edit it in
the standard ways, e.g. `kubectl edit projectmapping kubetruth-root`.  The
`override` scope allows you to override the root scope's behavior by matching
its `project_selector` pattern against the CloudTruth project names already
selected by the root `project_selector`.

Note that Kubetruth watches for changes to ProjectMappings, so touching any of
them wakes it up from a polling sleep.  This makes it quick and easy to test out
configuration changes without having a short polling interval.

To customize how things are named, edit the `*_template` properties in the
ProjectMappings.  These templates are processed using the [Liquid template
language](https://shopify.github.io/liquid/), and can reference the `project`
the `key` or any other named references from the `_selector` regexes.  In
addition to the built in liquid filters, kubetruth also define a few custom
ones:

 * dns_safe - ensures the string is safe for use as a kubernetes resource name (i.e. Namespace/ConfigMap/Secret names)
 * env_safe - ensures the string is safe for setting as a shell environment variable

### Example Config

The `projectmapping` resource has a shortname of `pm` for convenience when using kubectl.

To create kubernetes Resources in namespaces named after each Project:
```
kubectl patch pm kubetruth-root --type json --patch '[{"op": "replace", "path": "/spec/namespace_template", "value": "{{project | dns_safe}}"}]'
```

To include the parameters from a Project named `Base` into all other projects, without creating Resources for `Base` itself:
```
kubectl patch pm kubetruth-root --type json --patch '[{"op": "replace", "path": "/spec/included_projects", "value": ["Base"]}]'

kubectl apply -f - <<EOF
apiVersion: kubetruth.cloudtruth.com/v1
kind: ProjectMapping
metadata:
    name: exclude-base
spec:
    scope: override
    project_selector: "^Base$"
    skip: true
EOF
```
Note that project imports are non-recursive, so if A imports B and B imports C,
then A will only get B's parameters.

To override the naming of kubernetes Resources on a per-Project basis:
```
kubectl apply -f - <<EOF
apiVersion: kubetruth.cloudtruth.com/v1
kind: ProjectMapping
metadata:
  name: funkyproject-special-naming
spec:
    scope: override
    project_selector: funkyProject
    configmap_name_template: notSoFunkyConfigMap
    secret_name_template: notSoFunkySecret
    namespace_template: notSoFunkyNsmespace
EOF
```

To limit the Projects processed to those whose names start with `service`, except for `serviceOddball`:
```
kubectl patch pm kubetruth-root --type json --patch '[{"op": "replace", "path": "/spec/project_selector", "value": "^service"}]'

kubectl apply -f - <<EOF
apiVersion: kubetruth.cloudtruth.com/v1
kind: ProjectMapping
metadata:
  name: funkyproject-special-naming
spec:
  scope: override
  project_selector: serviceOddball
  skip: true
EOF
```

To see the ProjectMappings that have been setup
```
$ kubectl get pm
NAME                          SCOPE      PROJECT          AGE
exclude-base                  override   ^Base$           7m6s
funkyproject-special-naming   override   serviceOddball   13s
kubetruth-root                root       ^service         27m

$ kubectl describe pm kubetruth-root
Name:         kubetruth-root
Namespace:    default
Labels:       ...
Annotations:  ...
API Version:  kubetruth.cloudtruth.com/v1
Kind:         ProjectMapping
Metadata:
  ...
Spec:
  configmap_name_template:  {{project}}
  included_projects:
  key_filter:            
  key_selector:          
  key_template:          {{key}}
  namespace_template:    
  project_selector:      
  Scope:                 root
  secret_name_template:  {{project}}
  Skip:                  false
  skip_secrets:          false
Events:                  <none>
```
## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `bundle exec rspec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install and run via helm in a local cluster:
``` 
# If using minikube, ensure that docker builds the image into the minikube container
# with the command:
# eval $(minikube docker-env)
#
docker build -t kubetruth . && helm install \
    --set image.repository=kubetruth --set image.pullPolicy=Never --set image.tag=latest \
    --set appSettings.debug=true --set appSettings.apiKey=$CLOUDTRUTH_API_KEY --set appSettings.environment=development \
    kubetruth ./helm/kubetruth/
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/cloudtruth/kubetruth.
