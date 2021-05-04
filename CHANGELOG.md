0.4.0 (05/04/2021)
------------------

#### Notes on major changes

* \[breaking change] Template evaluation is now strict so existing templates may fail if they reference an invalid variable or filter

#### Full changelog

* extra tests around using templates and regex match assumptions [b47757d](../../commit/b47757d)
* refactor template processing to only parse templates during config load [8098da7](../../commit/8098da7)
* update comment [3a701d2](../../commit/3a701d2)
* enable creation/modification of mappings through helm configuration mechanism e.g. at install time [4e5703b](../../commit/4e5703b)
* doc fixes [4f01412](../../commit/4f01412)
* give anonymous class a name for visibility in logs [58dacfc](../../commit/58dacfc)
* make logging output more detailed [7f17c8d](../../commit/7f17c8d)
* Make template evaluation be strict (fails fast on invalid variable or filter references), benchmark run loop [8b00c1d](../../commit/8b00c1d)
* Make the dry run option exercise more of the code [8d9c9b4](../../commit/8d9c9b4)
* add headers to allow deep linking for for examples [853ef3a](../../commit/853ef3a)

0.3.0 (04/29/2021)
------------------

#### Notes on major changes

* Added support for CloudTruth Projects, with the ability to include data from 
* \[breaking change] Changed the generation of resource names to be based around the CloudTruth projects rather than a regex match against CloudTruth parameters.  You can still use named matches from regexes in templates used for generating resource names. 
* \[breaking change] Now using a CRD to configure behavior instead of helm configuration properties.  Helm properties are still used to control startup parameters.
* \[breaking change] Now using liquid for templates, `%{property}` => `{{property}}`

#### Full changelog

* cleanup release scripts [dab6015](../../commit/dab6015)
* update cli version [d9bbe0a](../../commit/d9bbe0a)
* mention overwrite protection [ba848c1](../../commit/ba848c1)
* update to use CLOUDTRUTH_API_KEY everywhere like cli does [7600981](../../commit/7600981)
* use liquid for template evaluation [9ef2fd1](../../commit/9ef2fd1)
* interrupt polling sleep on CRD changes [d3aaaa5](../../commit/d3aaaa5)
* don't cache projects since they are likely to change [4f91947](../../commit/4f91947)
* add project inclusion [7bfebf1](../../commit/7bfebf1)
* fix kube entity name conversion [3183535](../../commit/3183535)
* add a helmv2 specific chart [2ce7a47](../../commit/2ce7a47)
* add a helmv2 specific chart [2c997f7](../../commit/2c997f7)
* Configure via a CRD instead of a yaml file [50ffb44](../../commit/50ffb44)
* Add support for cloudtruth projects with the ability to merge data across projects, removed the regex dispatching from keys to configmap/secret names, moved config to a yaml file within a kubetruth configmap [822d7e1](../../commit/822d7e1)

0.2.2 (04/15/2021)
------------------

* mask secrets when debug logging [6a59a3f](../../commit/6a59a3f)
* fix helm template handling of list params [25f7e70](../../commit/25f7e70)
* fix typo [771eb3a](../../commit/771eb3a)

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
