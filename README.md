[![Build Status](https://github.com/cloudtruth/kubetruth/workflows/CD/badge.svg)](https://github.com/cloudtruth/kubetruth/actions)
[![Coverage Status](https://codecov.io/gh/cloudtruth/kubetruth/branch/master/graph/badge.svg)](https://codecov.io/gh/cloudtruth/kubetruth)
[![Configured by CloudTruth](https://img.shields.io/badge/configured--by-CloudTruth-blue.svg?style=plastic&labelColor=384047&color=00A6C0&link=https://cloudtruth.com)](https://cloudtruth.com)

# Kubetruth

The [CloudTruth integration for kubernetes](https://docs.cloudtruth.com/integrations/kubernetes) that pushes parameter updates into
kubernetes resources - usually ConfigMaps and Secrets, but any resource is
allowed.  The goal is to provide you a mechanism that is as hands off as
possible, using naming conventions to automate the delivery of configuration so
that you don't have to jump through setup hoops for each app/service/etc that
you would like to configure with CloudTruth

## Installation

```shell
helm repo add cloudtruth https://packages.cloudtruth.com/charts/
helm install \
    --set appSettings.apiKey=<api_key> \
    --set projectMappings.root.environment=<environment> \
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

Parameterize the helm install with `--set *` or `--values yourConfig.yaml` to control how kubetruth matches against your organization's naming conventions:

| Parameter | Description | Type | Default | Required |
|-----------|-------------|------|---------|:--------:|
| appSettings.apiKey | The CloudTruth api key.  Read only access is sufficient | string | n/a | yes |
| appSettings.pollingInterval | Interval to poll CloudTruth api for changes | integer | 300 | no |
| appSettings.debug | Debug logging and behavior | flag | false | no |
| projectMappings.root.environment | The CloudTruth environment to lookup parameter values for. | string | `default` | yes |
| projectMappings.root.project_selector | A regexp to limit the projects acted against (client-side).  Supplies any named matches for template evaluation | string | "" | no |
| projectMappings.root.key_selector | A regexp to limit the keys acted against (client-side).  Supplies any named matches for template evaluation | string | "" | no |
| projectMappings.root.skip | Skips the generation of resources for the selected projects | flag | false | no |
| projectMappings.root.included_projects | Include the parameters from other projects into the selected ones.  This can be recursive in a depth first fashion, so if A imports B and B imports C, then A will get B's and C's parameters.  For key conflicts, if A includes B and B includes C, then the precendence is A overrides B overrides C.  If A includes \[B, C], then the precendence is A overrides C overrides B. | list | [] | no |
| projectMappings.root.context | Additional variables made available to the resource templates.  Can also be templates | map | [default](helm/kubetruth/values.yaml#L93-L129) | no |
| projectMappings.root.resource_templates | The templates to use in generating kubernetes resources (ConfigMap/Secrets/other) | map | [default](helm/kubetruth/values.yaml#L93-L129) | no |
| projectMappings.<override_name>.* | Define override mappings to override settings from the root selector for specific projects. When doing this on the command-line (e.g. for `helm install`), it may be more convenient to use `--values <file>` instead of `--set` for large data sets | map | {} | no |

With the default `resource_templates`, Kubetruth maps the parameters from
CloudTruth Projects into ConfigMaps and Secrets of the same names as the
Projects. Kubetruth will not overwrite any existing kubernetes resources that do
not have the label `app.kubernetes.io/managed-by: kubetruth`.  If you have some
that you want kubetruth to manage, then either add the label or delete them
manually.

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
scope is required, and there can be only one per namespace (see
[below](#multi-instance-config)).  It sets up the global behavior for mapping
the CloudTruth projects to kubernetes resources.  You can edit it in the
standard ways, e.g. `kubectl edit projectmapping kubetruth-root`.  The
`override` scope allows you to override the root scope's behavior for those
CloudTruth projects whose names match its `project_selector` pattern.

Note that Kubetruth watches for changes to ProjectMappings, so touching any of
them wakes it up from a polling sleep.  This makes it quick and easy to test out
configuration changes without having a short polling interval.  You can also
force a wakeup by execing the wakeup script in the running container:

`kubectl exec deployment/kubetruth -- wakeup`

To customize how the kubernetes resources are generated, edit the
`resource_templates` property in the ProjectMappings.  These templates are
processed using the [Liquid template
language](https://shopify.github.io/liquid/), and can reference the following
liquid variables:

| Liquid Variables | Description |
|-----------------|-------------|
| `template` | The name of the template currently being rendered. |
| `kubetruth_namespace` | The namespace kubetruth is installed in. |
| `mapping_namespace` | The namespace that the current set of mappings exist in. |
| `project` | The project name. |
| `project_heirarchy` | The `included_projects` tree that this project includes. (useful to debug when using complex `included_projects`) |
| `debug` | Indicates if kubetruth is operating in debug (logging) mode. |
| `parameters` | The CloudTruth parameters from the project.|
| `parameter_origins` | The projects each parameter originates from. (useful to debug when using complex `included_projects`) |
| `secrets` | The CloudTruth secrets from the project. |
| `secret_origins` | The projects each secret originates from. (useful to debug when using complex `included_projects`)
| `context` | A hash of context variables supplied from ProjectMappings. (useful to override portions of templates without having to replace them completely in an override) |

In addition to the built in liquid filters, kubetruth also define a few custom
ones:
| Custom Filters  | Description |
|-----------------|-------------|
| `dns_safe` |  Ensures the string is safe for use as a kubernetes resource name (i.e. Namespace/ConfigMap/Secret names) | 
| `env_safe` |  Ensures the string is safe for setting as a shell environment variable | 
| `key_safe` |  Ensures the string is safe for use as a key inside a ConfigMap/Secret data hash | 
| `indent: count` |  Indents each line in the argument by count spaces | 
| `nindent: count` |  Adds a leading newline, then indents each line in the argument by count spaces | 
| `stringify` |  Converts argument to a staring safe to use in yaml (escapes quotes and surrounds with the quote character) | 
| `to_yaml` |  Converts argument to a yaml representation | 
| `to_json` |  Converts argument to a json representation | 
| `encode64` |  The argument bas64 encoded | 
| `decode64` |  The argument bas64 decoded | 
| `sha256` |  The sha256 digest of the argument | 

The default `resource_templates` make use of the `context` attribute to allow
simpler modification of some common fields.  These include:
| Context Variables | Description |
|-------------------|-------------|
| `context.resource_name` | set this in a ProjectMapping to supply a different name to the the default templates |
| `context.resource_namespace` | set this in a ProjectMapping to supply a different namespace to the default templates |
| `context.skip_secrets` | set this in a ProjectMapping to prevent output of a Secret resource even when secrets are present |

Since the `context` is a freeform map type, you can add custom items to it, as
well as architect any custom templates to make use of those custom items in the
same way the default templates do.  If the value of a `context` entry is a
string, it is treated as a template, and can reference and set variables in the
resource_template that is evaluating it.  If the value is of some other yaml
type (e.g. boolean/number/list/map), it will get passed through as that type to
the template that is referencing it, so you can use it in more complex template
logic like `{% foreach item in context.my_items %}`

The default `resource_templates` add the `parameter_origins` and `project_heirarchy`
key as annotations on each kubernetes resource under management.  This can be
disabled by removing them from the template, or wrapping them in a test for
`debug`.  The data produced by these help to illustrate how project inclusion
affects the project the resources were written for.   It currently shows the
project heirarchy and the project each parameter originates from, for example an
entry like `timeout: myService (commonService -> common)` indicates that the
timeout parameter is getting its value from the `myService` project, and if you
removed it from there, it would then get it from the `commonService` project,
and if you removed that, it would then get it from the `common` project.

### Multi Instance Config

By default, Kubetruth is setup with a single set of ProjectMapping CRDs
installed into the same namespace it was installed to.  These are the `primary`
CRDs.  For systems that use independent kubernetes clusters per environment,
this is all that you need.  If, however, you'd like to be able to run multiple
`environments` in the same cluster, you can make use of the multi-instance
feature of kubetruth.

To do so, one simply needs to create ProjectMapping CRDs in namespaces other
than the primary.  These CRDs will automatically inherit the contents of the CRD
of the same name from the primary namespace, and you can then selectively
override the attributes you need to change for the supplemental instance.  This
allows you to reuse all the templates/logic/etc that you setup in the primary,
and only have to change the differing dimension.  See the `environment` [example
below](#environment-per-namespace)

### Example Config

The `projectmapping` resource has a shortname of `pm` for convenience when using kubectl.

#### Namespace per Project

To create kubernetes Resources in namespaces named after each Project:
```
kubectl edit pm kubetruth-root
```
and set the `context.resource_namespace` field:
```
spec:
    context:
        resource_namespace: '{{ project | dns_safe }}'
```

Or to do it with `kubectl patch`:

```
kubectl patch pm kubetruth-root --type json --patch '[{"op": "replace", "path": "/spec/context/resource_namespace", "value": "{{ project | dns_safe }}"}]'
```

Or to do it at install time, add the following to the `helm install` command:

```
--set projectMappings.root.context.resource_namespace="\{\{ project | dns_safe \}\}"
```

#### Share common data

To include the parameters from a Project named `Base` into all other projects, without creating Resources for `Base` itself:
```
# Set the included_project in the root mapping
kubectl patch pm kubetruth-root --type json --patch '[{"op": "replace", "path": "/spec/included_projects", "value": ["Base"]}]'

# Exclude the Base project by creating an override mapping that skips it:
kubectl apply -f - <<EOF
apiVersion: kubetruth.cloudtruth.com/v1
kind: ProjectMapping
metadata:
    name: exclude-base
spec:
    scope: override
    project_selector: "^Base$"
    skip: true
    included_projects: []
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
    context:
        resource_name: notSoFunkyConfigMap
        resource_namespace: notSoFunkyNamespace
EOF
```

#### Environment per namespace

To setup an environment per namespace:
```
# Disable output from the primary (optional)
kubectl patch pm kubetruth-root --type json --patch '[{"op": "replace", "path": "/spec/skip", "value": "true"}]'

# Tag each namespace that you'd like to have its own environment
kubectl --namespace <your_namespace> apply -f - <<EOF
apiVersion: kubetruth.cloudtruth.com/v1
kind: ProjectMapping
metadata:
  name: kubetruth-root
spec:
  scope: root
  environment: loadtest
  skip: false
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
<snipped>
```

## Development

After checking out the repo, run `bundle` to install dependencies. Then, run
`bundle exec rspec` to run the tests. You can also run `bundle exec rake console` for an
interactive prompt that will allow you to experiment.

To install and run via helm in a local cluster:
``` 
mkdir local
cat > local/values.yml <<-EOF
image:
  repository: kubetruth
  pullPolicy: Never
  tag: latest
appSettings:
  debug: true
  apiKey: <your_api_key>
EOF

rake install

# OR

# If using minikube, ensure that docker builds the image into the minikube container
# with the command:
# eval $(minikube docker-env)
#
docker build --release development -t kubetruth . && helm install \
    --set image.repository=kubetruth --set image.pullPolicy=Never --set image.tag=latest \
    --set appSettings.debug=true --set appSettings.apiKey=$CLOUDTRUTH_API_KEY \
    kubetruth ./helm/kubetruth/
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/cloudtruth/kubetruth.
