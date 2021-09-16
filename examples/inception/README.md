# Using kubetruth to configure kubetruth

This example uses kubetruth to configure kubetruth by creating kubetruth
ProjectMapping CRDs from the CloudTruth project named kubetruth.

It provides 2 variants:

* `values-parameter-driven.yaml`:
  The CloudTruth parameters are organized according to their dot-notated keys to
  simulate a hash of the attributes for the CRD and then a CRD yaml is created
  and applied for each grouping.  For example with CloudTruth parameters like the following:
    ```
    foo.project_selector: ^foo$
    foo.skip: true
    bar.project_selector: ^bar$
    bar.resource_templates.secret: ""
    ```
  kubetruth will create a CRD named foo, that skips processing for the project named foo, and
  another CRD named bar that prevents generation of the default secret resource by
  setting its template to empty
* `values-template-driven.yaml`:
  Each CloudTruth template is treated as a complete CRD yaml and applied verbatim

## Setup CloudTruth Credentials

Login to CloudTruth, and create an api key, then add it to your environment

```
export CLOUDTRUTH_API_KEY=your_api_key
```

## Setup a project to configure the deploy

```
cloudtruth projects set kubetruth
```

## (Optional) Setup [minikube](https://minikube.sigs.k8s.io/docs/start/) to test locally
```
minikube start
```

## Setup kubetruth to apply a deployment resource for that project

To try the parameter driven variant, install kubetruth with the following settings:
```
helm install --values examples/inception/values-parameter-driven.yaml --set appSettings.apiKey=$CLOUDTRUTH_API_KEY kubetruth cloudtruth/kubetruth
```

OR to try the template driven variant variant, install kubetruth like:
```
helm install --values examples/inception/values-template-driven.yaml --set appSettings.apiKey=$CLOUDTRUTH_API_KEY kubetruth cloudtruth/kubetruth
```

## Check kubetruth is up

```
kubectl describe deployment kubetruth
kubectl logs deployment/kubetruth
```

## Add a project that we can affect with a CRD

```
cloudtruth projects set nosecret
cloudtruth --project nosecret parameter set --value myval aParam
cloudtruth --project nosecret parameter set --secret true --value sekret aSecret
```

Note that no resources get generated for it yet since our root selector was set to skip all:
```
kubectl describe configmap nosecret
kubectl describe secret nosecret
```

## Create and verify a parameter-driven CRD

If you installed kubetruth using the parameter driven variant of this example,
create some CloudTruth parameters to be interpreted as a CRD:
```
cloudtruth --project kubetruth parameter set --value "^nosecret$" nosecret.project_selector 
cloudtruth --project kubetruth parameter set --value "" nosecret.resource_templates.secret
cloudtruth --project kubetruth parameter set --value "false" nosecret.skip # we skipped globally in the root, so need to undo it
```

Note that a ConfigMap gets generated, but a Secret does not:
```
kubectl describe configmap nosecret 
kubectl describe secret nosecret
```

Re-enable Secret generation:
```
cloudtruth --project kubetruth parameter delete nosecret.resource_templates.secret
```

Note that a Secret is now being generated:
```
kubectl describe secret nosecret # a Secret resource should now be generated
```

## Create and verify a template-driven CRD

If you installed kubetruth using the template driven variant of this example, create a CloudTruth template to be written as the CRD:

```
cloudtruth --project kubetruth template set --body examples/inception/nosecret.tmpl.yaml nosecret
```

Similar steps can be followed to verify the behavior like one does in the parameter driven variant
