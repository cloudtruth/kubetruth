# Using kubetruth to trigger reload/restart of pre-existing app

This example uses kubetruth to patch a kubernetes deployment whenever dependent parameters change

## Setup CloudTruth Credentials

Login to CloudTruth, and create an api key, then add it to your environment

```
export CLOUDTRUTH_API_KEY=your_api_key
```

## (Optional) Setup [minikube](https://minikube.sigs.k8s.io/docs/start/) to test locally
```
minikube start
```

# Deploy a pre-existing application

```
kubectl apply -f examples/deploymentpatch/deployment.yaml
```

## Check service is up, note environment vars

```
kubectl describe deployment deploypatchtest
kubectl get deployment/deploypatchtest -o yaml | grep -A2 envFrom:
kubectl exec deployment/deploypatchtest -- printenv | grep MY_ENV
```

## Setup a project to configure the environment

```
cloudtruth projects set deploypatchtest

cloudtruth --project deploypatchtest parameter set --value "Hello from patch" MY_ENV_HELLO
cloudtruth --project deploypatchtest parameter set --value "Goodbye from patch" MY_ENV_GOODBYE
```

## Setup kubetruth to create a configmap and patch pre-existing deployment resource for that project

Install kubetruth with the settings that enable deployment patching:
```
helm install --values examples/deploymentpatch/values.yaml --set appSettings.apiKey=$CLOUDTRUTH_API_KEY kubetruth cloudtruth/kubetruth
```

## Check kubetruth is up

```
kubectl describe deployment kubetruth
kubectl logs deployment/kubetruth
```

Note that you can ignore the warning:

```
Skipping 'default:Deployment:deploypatchtest' as it doesn't have a label indicating it is under kubetruth management
```
This is expected as kubetruth won't touch any resources that it didn't create unless they are labelled like we do in the next step.

## Allow kubetruth to patch existing deployment

```
kubectl label deployment/deploypatchtest app.kubernetes.io/managed-by=kubetruth
```

## Wake kubetruth from polling sleep

```
kubectl exec deployment/kubetruth -- wakeup
```

## Check service environment vars

```
kubectl get deployment/deploypatchtest -o yaml | grep -A2 envFrom:
kubectl exec deployment/deploypatchtest -- printenv | grep MY_ENV
```

## Trigger an update

```
cloudtruth --project deploypatchtest parameter set --value "A New Hello from patch" MY_ENV_HELLO
kubectl exec deployment/kubetruth -- wakeup
```

## Check service environment vars

```
kubectl get deployment/deploypatchtest -o yaml | grep -A2 envFrom:
kubectl exec deployment/deploypatchtest -- printenv | grep MY_ENV
```
