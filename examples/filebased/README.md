# Using kubetruth to produce file based configmaps

This example uses kubetruth to create configmaps with structured config files for each project

Reasons you might want a file based configmap

 * Your components already take files to configure themselves, and you want cloudtruth/kubetruth to be as drop-in as possible
 * You want to take advantage of the in-place updates of ConfigMap/Secret files in a running container without restarts
 * You like having structured config which is prevented by the flat nature of kubernetes ConfigMaps/Secrets

## Setup CloudTruth Credentials

Login to CloudTruth, and create an api key, then add it to your environment

```
export CLOUDTRUTH_API_KEY=your_api_key
```

## Setup a project to configure the deploy

```
cloudtruth projects set filetest

cloudtruth --project filetest parameter set --value hi foo.yml/bar
cloudtruth --project filetest parameter set --value yum foo.yml/baz/boo
cloudtruth --project filetest parameter set --value fun foo.yml/baz/bum
cloudtruth --project filetest parameter set --value myval bar.json/other
```

## (Optional) Setup [minikube](https://minikube.sigs.k8s.io/docs/start/) to test locally
```
minikube start
```

## Setup kubetruth to apply a deployment resource for that project

Install kubetruth with the following settings:
```
helm install --values examples/filebased/values.yaml --set appSettings.apiKey=$CLOUDTRUTH_API_KEY kubetruth cloudtruth/kubetruth
```

## Check kubetruth is up

```
kubectl describe deployment kubetruth
kubectl logs deployment/kubetruth
```

## Check configmap was generated

```
kubectl describe configmap filetest
```
results in

```
Name:         filetest
Namespace:    default
Labels:       app.kubernetes.io/managed-by=kubetruth
              version=51988e7
Annotations:  kubetruth/parameter_origins:
                ---
                bar.json/other: filetest
                foo.yml/bar: filetest
                foo.yml/baz/boo: filetest
                foo.yml/baz/bum: filetest
              kubetruth/project_heirarchy:
                ---
                filetest: {}

Data
====
foo.yml:
----
---
bar: hi
baz:
  boo: yum
  bum: fun

bar.json:
----
{"other":"myval"}

Events:  <none>
```