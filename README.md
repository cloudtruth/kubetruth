[![Build Status](https://github.com/cloudtruth/kubetruth/workflows/CD/badge.svg)](https://github.com/cloudtruth/kubetruth/actions)
[![Coverage Status](https://codecov.io/gh/cloudtruth/kubetruth/branch/master/graph/badge.svg)](https://codecov.io/gh/cloudtruth/kubetruth)
[![Configured by CloudTruth](https://img.shields.io/badge/configured--by-CloudTruth-blue.svg?style=plastic&labelColor=384047&color=00A6C0&link=https://cloudtruth.com)](https://cloudtruth.com)

# Kubetruth

The CloudTruth integration for kubernetes that pushes parameter updates into
kubernetes resources (usually config maps and secrets).  The goal is to provide
you a mechanism that is as hands off as possible, using naming conventions to
automate the delivery of configuration so that you don't have to jump through
setup hoops for each app/service/etc that you would like to configure with
CloudTruth

## Installation

```shell
helm repo add cloudtruth https://packages.cloudtruth.com/charts/
helm install \
    --set appSettings.apiKey=<api_key> \
    --set appSettings.environment=<environment> \
    kubetruth cloudtruth/kubetruth
```

Note that the helm release name (`kubetruth` above) is used in generating the
names of the resources created at install time.  Thus in the examples below, a
name like `kubetruth-root` for the default installed CRD would be different in
your system if you gave `helm install` a different release name.

## Uninstall

```shell
helm delete kubetruth
helm repo remove cloudtruth
```

## Usage

Parameterize the helm install with `--set appSettings.**` to control how kubetruth matches against your organization's naming conventions:

| Parameter | Description | Type | Default | Required |
|-----------|-------------|------|---------|:--------:|
| appSettings.apiKey | The CloudTruth api key.  Read only access is sufficient | string | n/a | yes |
| appSettings.environment | The CloudTruth environment to lookup parameter values for.  Use a separate helm install for each environment | string | `default` | yes |
| appSettings.pollingInterval | Interval to poll CloudTruth api for changes | integer | 300 | no |
| appSettings.debug | Debug logging and behavior | flag | false | no |
| projectMappings.root.project_selector | A regexp to limit the projects acted against (client-side).  Supplies any named matches for template evaluation | string | "" | no |
| projectMappings.root.key_selector | A regexp to limit the keys acted against (client-side).  Supplies any named matches for template evaluation | string | "" | no |
| projectMappings.root.skip | Skips the generation of resources for the selected projects | flag | false | no |
| projectMappings.root.skip_secrets | Prevent transfer of secrets to kubernetes Secrets | flag | false | no |
| projectMappings.root.included_projects | Include the parameters from other projects into the selected ones.  This can be recursive in a depth first fashion, so if A imports B and B imports C, then A will get B's and C's parameters.  For key conflicts, if A includes B and B includes C, then the precendence is A overrides B overrides C.  If A includes \[B, C], then the precendence is A overrides C overrides B. | list | [] | no |
| projectMappings.root.configmap_template | The template to use in generating a kubernetes resource (ConfigMap) for non-secret parameters | string | [default](helm/kubetruth/values.yaml#L94-L108) | no |
| projectMappings.root.secret_template | The template to use in generating a kubernetes resource (Secret) for secret parameters | string | [default](helm/kubetruth/values.yaml#L110-L124) | no |
| projectMappings.<override_name>.* | Define override mappings to override settings from the root selector for specific projects. When doing this on the command-line (e.g. for `helm install`), it may be more convenient to use `--values <file>` instead of `--set` for large data sets | map | {} | no |

By default, Kubetruth maps the parameters from CloudTruth Projects into
ConfigMaps and Secrets of the same names as the Projects. Kubetruth will not
overwrite any existing kubernetes resources that do not have the label
`app.kubernetes.io/managed-by: kubetruth`.  If you have some that you want
kubetruth to manage, then either add the label or delete them manually.

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
    mySecret: value4
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
restarting the pod on a ConfigMap change, or read config from mounted volumes
for configmaps/secrets, which do get updated automatically in a running pod.

## Additional configuration

Kubetruth uses a CustomResourceDefinition called
[ProjectMapping(.kubetruth.cloudtruth.com)](helm/kubetruth/crds/projectmapping.yaml)
for additional configuration.  The ProjectMapping CRD has two types identified
by the `scope` property, the `root` scope and the `override` scope.  The `root`
scope is required, and there can be only one.  It sets up the global behavior
for mapping the CloudTruth projects to kubernetes resources.  You can edit it in
the standard ways, e.g. `kubectl edit projectmapping kubetruth-root`.  The
`override` scope allows you to override the root scope's behavior for those
CloudTruth projects whose names match its `project_selector` pattern.

Note that Kubetruth watches for changes to ProjectMappings, so touching any of
them wakes it up from a polling sleep.  This makes it quick and easy to test out
configuration changes without having a short polling interval.

To customize how the kubernetes resources are generated, edit the `*_template` properties in the
ProjectMappings.  These templates are processed using the [Liquid template
language](https://shopify.github.io/liquid/), and can reference the following liquid variables:

 * `project` - The project name
 * `project_heirarchy` - The `included_projects` tree this project includes (useful to debug when using complex `included_projects`)
 * `parameters` - The CloudTruth parameters from the project
 * `parameter_origins` - The projects each parameter originates from (useful to debug when using complex `included_projects`)
 * `debug` - Indicates if kubetruth is operating in debug (logging) mode.

In addition to the built in liquid filters, kubetruth also define a few custom
ones:

 * `dns_safe` - Ensures the string is safe for use as a kubernetes resource name (i.e. Namespace/ConfigMap/Secret names)
 * `env_safe` - Ensures the string is safe for setting as a shell environment variable
 * `indent: count` - Indents each line in the argument by count spaces
 * `nindent: count` - Adds a leading newline, then indents each line in the argument by count spaces
 * `stringify` - Converts argument to a staring safe to use in yaml (escapes quotes and surrounds with the quote character)
 * `to_yaml` - Converts argument to a yaml representation
 * `to_json` - Converts argument to a json representation
 * `encode64` - The argument bas64 encoded
 * `decode64` - The argument bas64 decoded
 * `sha256` - The sha256 digest of the argument

The default `*_template`s  add the `parameter_origins` and `project_heirarchy`
key as annotations on each kubernetes resource under management.  This can be
disabled by removing them from the template, or wrapping them in a test for
`debug`.  The data produced by these help to illustrate how project inclusion
affects the project the resources were written for.   It currently shows the
project heirarchy and the project each parameter originates from, for example an
entry like `timeout: myService (commonService -> common)` indicates that the
timeout parameter is getting its value from the `myService` project, and if you
removed it from there, it would then get it from the `commonService` project,
and if you removed that, it would then get it from the `common` project.

### Example Config

The `projectmapping` resource has a shortname of `pm` for convenience when using kubectl.

#### Namespace per Project

To create kubernetes Resources in namespaces named after each Project:
```
kubectl edit pm kubetruth-root
```
and add the metadata.namespace field to configmap_template and secret_template like so:
```yaml
spec:
  configmap_template: |
    apiVersion: v1
    kind: ConfigMap
    metadata:
        namespace: {{ project | dns_safe }}
```

#### Share common data

To include the parameters from a Project named `Base` into all other projects, without creating Resources for `Base` itself:
```
# Set the included_project in the root mapping
kubectl patch pm kubetruth-root --type json --patch '[{"op": "replace", "path": "/spec/included_projects", "value": ["Base"]}]'

# Either exclude the Base project from being matched in the root mapping:
kubectl patch pm kubetruth-root --type json --patch '[{"op": "replace", "path": "/spec/project_selector", "value": "^(?!Base)"}]'

# OR exclude the Base project by creating an override mapping that skips it:
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

#### Customize naming of Resources

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
    configmap_template: |
        apiVersion: v1
        kind: ConfigMap
        metadata:
            namespace: notSoFunkyNamespace
            name: notSoFunkyConfigMap
        <snipped>
    secret_template: |
        apiVersion: v1
        kind: Secret
        metadata:
            namespace: notSoFunkyNamespace
            name: notSoFunkySecret
        <snipped>
EOF
```

#### More specific project selection

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
  <snipped>
Spec:
  configmap_template: |
    <snipped>
  secret_template: |
    <snipped>
  included_projects:
  key_selector:          
  project_selector:      
  scope:                 root
  skip:                  false
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
