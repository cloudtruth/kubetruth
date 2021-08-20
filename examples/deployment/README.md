# Using kubetruth to deploy

This example uses kubetruth to apply a kubernetes deployment whenever dependent parameters change (e.g. `image_version`)

It provides 2 variants:

 * `values-simple.yaml`:
   The deployment templates are fairly simple and hosted within the cloudtruth
   templating system (`deploy.yaml.tmpl`).  Sharing of templates across multiple
   projects has not yet been implemented in the cloudtruth engine, so this
   method is not very modular and you'll have to fully define the deployment
   template for each project.  However, it is a lot easier to grok
 * `values-modular.yaml`:
   The deployment templates are defined within kubetruth and as such can be
   reused across multiple projects, as well as setting up the metadata to make
   use of the kubetruth ability to apply to multiple namespaces/environments
   within the same cluster

If you set this up within your own infrastructure, then you can easily deploy
from CI after test/build by running the [cloudtruth cli to set the new version](#trigger-a-deploy).

## Setup CloudTruth Credentials

Login to CloudTruth, and create an api key, then add it to your environment

```
export CLOUDTRUTH_API_KEY=your_api_key
```

## Setup a project to configure the deploy

```
cloudtruth projects set deploytest

cloudtruth --project deploytest parameter set --value nginx app_name
cloudtruth --project deploytest parameter set --value 80 app_port
cloudtruth --project deploytest parameter set --value nginx image_name
cloudtruth --project deploytest parameter set --value 1.20 image_version

# Only needed when using the values-simple.yaml variant
cloudtruth --project deploytest template set --body examples/deployment/deploy.yaml.tmpl deployment
```

## (Optional) Setup [minikube](https://minikube.sigs.k8s.io/docs/start/) to test locally
```
minikube start
```

## Setup kubetruth to apply a deployment resource for that project

To try the simple variant, install kubetruth with the following settings:
```
helm install --values examples/deployment/values-simple.yaml --set appSettings.apiKey=$CLOUDTRUTH_API_KEY kubetruth cloudtruth/kubetruth
```

OR to try the modular variant, install kubetruth like:
```
helm install --values examples/deployment/values-complete.yaml --set appSettings.apiKey=$CLOUDTRUTH_API_KEY kubetruth cloudtruth/kubetruth
```

## Check kubetruth is up

```
kubectl describe deployment kubetruth
kubectl logs deployment/kubetruth
```

## Check service is up, note version

```
kubectl describe deployment nginx | grep -i image
minikube service nginx # force a 404 to see nginx version string
```

## Trigger a deploy

```
cloudtruth --project deploytest parameter set --value 1.21 image_version
```

## Check service is up, note version

```
kubectl describe deployment nginx | grep -i image
minikube service nginx # force a 404 to see nginx version string
```
