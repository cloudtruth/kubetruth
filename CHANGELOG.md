0.2.1 (02/24/2021)
------------------

* use minikube for testing as its permissions are more standard (rigorous) by default compared to docker-desktop [ef16657](../../commit/ef16657)
* add ClusterRole and ClusterRoleBinding to allow cross namespace access [561a06c](../../commit/561a06c)

0.2.0 (02/17/2021)
------------------

* Only write to resources (ConfigMaps and Secrets) that are labeled as being under kubetruth management [e36f661](../../commit/e36f661)
* Label the kube resources that are created/updated by kubetruth [35aeefc](../../commit/35aeefc)
* Add the ability to use a namespaceTemplate to determine which namespace the kube resources will be created in [23707a7](../../commit/23707a7)

0.1.0 (12/07/2020)
------------------

Initial Release
