0.5.0 (06/18/2021)
------------------

#### Notes on major changes

* \[breaking change] Kubetruth can now generate any kubernetes resource via the templates supplied `resource_templates` attribute in ProjectMappings.  The default root ProjectMapping contains templates for ConfigMaps and Secrets
* \[breaking change] Removed these settings from ProjectMapping:
    * `key_filter` - use `key_selector` instead
    * `configmap_name_template` - use `context.resource_name` or supply your own `resource_templates`
    * `secret_name_template` - use `context.resource_name` or supply your own `resource_templates`
    * `namespace_template` - use `context.resource_namespace` or supply your own `resource_templates`
    * `key_template` - supply your own `resource_templates`
    * `skip_secrets` - use `context.skip_secrets` or supply your own `resource_templates`
* \[breaking change] Regular expression named matches are no longer used to supply template evaluation variables

#### Full changelog

* test ruby directly as running codecov within docker is messy [986b14c](../../commit/986b14c)
* cleanup repo structure [54096a1](../../commit/54096a1)
* remove conditional update as server-side apply takes care of it [7de290f](../../commit/7de290f)
* add a signal handler to wake up from polling sleep [c9c3873](../../commit/c9c3873)
* fix creating namespace [9db00b4](../../commit/9db00b4)
* add context to projectmappings to allow for small modifications (e.g. name, namespace) without having to replace the entire template Made resource_templates into a map, and made override merging of it (and context) be additive in nature so one can add a new mapping with a template without having to replace the existing ones [5d5646b](../../commit/5d5646b)
* add a key_safe filter to ensure ConfigMap/Secret keys are converted to something safe to use [6ef09e1](../../commit/6ef09e1)
* update readme [3249752](../../commit/3249752)
* update readme [bea9ff1](../../commit/bea9ff1)
* Use a list of resource_templates instead of specifically named ones for configmaps and secrets [63d961f](../../commit/63d961f)
* update for new version [353d422](../../commit/353d422)
* Major refactoring to allow using a template for the entire kuberenetes resources (ConfigMaps/Secrets/others) created for each project. [f76e9d2](../../commit/f76e9d2)

0.4.1 (05/19/2021)
------------------

* Add cloudtruth_metadata attribute to kubernetes resources (#5) [157eda7](../../commit/157eda7)
* switch readme badge to codecov [38ccd10](../../commit/38ccd10)
* switch to codecov [80b361d](../../commit/80b361d)

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
