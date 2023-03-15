1.2.3 (03/15/2023)
------------------

* update bundle [ebe13f2](../../commit/ebe13f2)
* test fixes for latest api spec [1e9b850](../../commit/1e9b850)
* Use non-root user and prevent writing to Gemfile.lock at runtime [e54c66a](../../commit/e54c66a)
* [sc-9270]cloudtruth-kubetruth-workflow-updates-part1 (#16) [430e3e0](../../commit/430e3e0)

1.2.2 (10/15/2022)
------------------

* fix missing logger [f01ef16](../../commit/f01ef16)

1.2.1 (10/07/2022)
------------------

* Honor tags when referencing an upstream cloudtruth template Only fetch parameters if the local template uses them [981d371](../../commit/981d371)
* add ability to run without async for easier debugging [cfe52f3](../../commit/cfe52f3)
* ignore empty stream templates [9791457](../../commit/9791457)

1.2.0 (05/18/2022)
------------------

* update docs [0230c51](../../commit/0230c51)
* Allow for the use of external secrets (#15) [241ece3](../../commit/241ece3)
* doc fix [00912cc](../../commit/00912cc)

1.1.1 (01/24/2022)
------------------

* add built in control of kubetruth from cloudtruth UI (disabled by default) [bdb23eb](../../commit/bdb23eb)
* add parse yml/json filters [ec53ec2](../../commit/ec53ec2)
* add mutex for namespace creation [87645e7](../../commit/87645e7)
* option to exclude CRDs from multi-instance/namespace inheritance [217639a](../../commit/217639a)
* add a re_contains filter for rgex string comparison [464b848](../../commit/464b848)
* fix spec for active_templates to allow it to be unset [a3a6cab](../../commit/a3a6cab)
* allow specifying namespace for projectmappings in values.yaml [554a43e](../../commit/554a43e)
* fix example [af961d1](../../commit/af961d1)

1.1.0 (01/04/2022)
------------------

* fix typing due to api change [f3914d4](../../commit/f3914d4)
* tweak dev environment [8a207a6](../../commit/8a207a6)
* add example on using kubetruth to patch existing deployments [6da7071](../../commit/6da7071)
* allow an alternate management label on kube resources [2315f9e](../../commit/2315f9e)
* rename mconcat to merge [b66107a](../../commit/b66107a)
* add active_templates in crd to make it easier to selectively enable of templates [3399bce](../../commit/3399bce)
* make typify handle collections, add mconcat and re_replace filters [ffc8563](../../commit/ffc8563)
* fix multi env/ns docs [0f3c4ee](../../commit/0f3c4ee)
* update test fixtures for new openapi spec [230f662](../../commit/230f662)
* add liquid filter deflate for completeness (inverse of inflate) [1c31661](../../commit/1c31661)
* update client generation [29b9ab7](../../commit/29b9ab7)
* add security policy [82ebf82](../../commit/82ebf82)
* update config action [e8880f7](../../commit/e8880f7)
* skip sleep after a CRD write so the next iteration can immediately process CRD changes [5751ae4](../../commit/5751ae4)
* catch more error types when rendering template to make it obvious the error is in a template [9036e07](../../commit/9036e07)
* add support for gating parameter values by version tag [74c3cc6](../../commit/74c3cc6)
* fix tests [3246b96](../../commit/3246b96)
* enable setting of log level from project mapping crds [8cca242](../../commit/8cca242)
* fix typo [095587c](../../commit/095587c)
* preserve parameter types returned from cloudtruth api, update openapi [865f16f](../../commit/865f16f)
* fix multiline secret asking [a055741](../../commit/a055741)
* add the typify filter [0089877](../../commit/0089877)
* fix title [6f272c2](../../commit/6f272c2)
* add example for using kubetruth to generate CRDs that control kubetruth [25b09d3](../../commit/25b09d3)
* make filter options explicitly named [9fef257](../../commit/9fef257)
* format template error message so cause is up front [a61671c](../../commit/a61671c)
* fix typo [1eee1f6](../../commit/1eee1f6)
* show output in filebased example [18c9756](../../commit/18c9756)
* add a file based configmap example [5f2a51b](../../commit/5f2a51b)
* add the ability for the liquid tester cli to read template variables from a file [a09e02c](../../commit/a09e02c)
* document restarts on configmap/secret changes [d917455](../../commit/d917455)

1.0.4 (08/20/2021)
------------------

* add an example of deploying with kubetruth [7275641](../../commit/7275641)
* allow replacing/adding rules to the role at install time, skip namespace role when installing cluster role [810c8fd](../../commit/810c8fd)

1.0.3 (08/06/2021)
------------------

* add an inflate filter to make it easy to convert a flat map to a nested data structure, e.g. `{foo.baz.bum: 2}` => `{foo: {bar: {baz: 2}}}` [0d0050b](../../commit/0d0050b)

1.0.2 (08/04/2021)
------------------

* add the ability to use cloudtruth templates within a kubetruth template [70ac60f](../../commit/70ac60f)

1.0.1 (08/02/2021)
------------------

* open cloudtruth openapi spec [6995a3e](../../commit/6995a3e)
* fix typo [4a5a36e](../../commit/4a5a36e)
* install less in container for rake console [afdeae6](../../commit/afdeae6)
* point coverage badge to correct branch [0523446](../../commit/0523446)

1.0.0 (07/22/2021)
------------------

#### Notes on major changes

* \[breaking change] Updated to use the new Cloudtruth REST API

#### Full changelog

* exclude params with nil values from templates [65966f8](../../commit/65966f8)
* latest api schema [079657e](../../commit/079657e)
* fix NPE - values are nil if unset [4c5ac74](../../commit/4c5ac74)
* run console through docker [3ad434b](../../commit/3ad434b)
* Use correct default API host [63a54bc](../../commit/63a54bc)
* check for minikube for rake install [0098866](../../commit/0098866)
* convenience tasks [3b4fe55](../../commit/3b4fe55)
* latest api schema [b76eb58](../../commit/b76eb58)
* yield task in async helper [0b53d64](../../commit/0b53d64)
* use logger for async exceptions [5cf8639](../../commit/5cf8639)
* allow overriding of image name when building docker image [60dd50a](../../commit/60dd50a)
* allow setting ct api url at install time [8561036](../../commit/8561036)
* add tests to validate concurrency for http calls.  Use faradat instead of typhoeus in generated client lib to get concurrency for ctapi [d194ac6](../../commit/d194ac6)
* explicit async wait at top level to future proof if sibling asyncs are added [d1d3992](../../commit/d1d3992)
* ignore coverage for generated client lib [2d540c0](../../commit/2d540c0)
* initial conversion to use cloudtruth rest api [22b3584](../../commit/22b3584)
* complete test coverage [366e919](../../commit/366e919)

0.6.0 (07/07/2021)
------------------

#### Notes on major changes

* \[breaking change] Setting environment at install time is now done through the CRD: `--set projectMappings.root.environment=<env>` instead of `--set appSettings.environment=<env>`
* \[breaking change] Selecting organization at install time is no longer allowed
* Kubetruth is now able to run for multiple environments in the same cluster by creating ProjectMapping CRDs in additional namespaces
* Upgraded to ruby v3 and using async to improve concurrency (event loop runtime shows a 2-3X improvement)
* Templates can now contain multiple YAML documents with use of the `---` YAML directive to separate them

#### Full changelog

* Merge pull request #10 from cloudtruth/async [3bf2048](../../commit/3bf2048)
* Merge pull request #9 from cloudtruth/environments_in_pms [913833a](../../commit/913833a)
* upgrade to ruby 3 to use async Use async for concurrency during IO [1b82bad](../../commit/1b82bad)
* cleanup appSettings.environment from deployment template [f72bbd7](../../commit/f72bbd7)
* watch for crd changes during sleep instead of during all of the apply so that CRDs that get written by kubetruth don't trigger a watch event [3fac73e](../../commit/3fac73e)
* update install command [6adb365](../../commit/6adb365)
* allow resources to be created for different api groups (crds) [e5458fc](../../commit/e5458fc)
* allow multiple yml docs in templates [aa78857](../../commit/aa78857)
* update readme for multi instance [19180c0](../../commit/19180c0)
* Move setting of environment to CRD Remove organization as the multiple org feature is no longer available Scan all namespaces for CRDs CRDs in namespaces other than the one kubetruth is installed in (the primary) are merged with those in the primary and trigger kubetruth to run them as a separate instance.  This makes it easy to run kubetruth for multiple environments in the same cluster by allowing full reuse of a single set templates/crds/etc across environments. [d0ef48c](../../commit/d0ef48c)
* Updated README formats (#8) [37daf2b](../../commit/37daf2b)

0.5.0 (06/22/2021)
------------------

#### Notes on major changes

* Kubetruth's polling sleep can be woken up with `kubectl exec deployment/kubetruth -- wakeup`
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

* fix masking of multiline secrets [88c8676](../../commit/88c8676)
* mask secrets in template debug logging [bf4bf81](../../commit/bf4bf81)
* Update readme [7c3e53c](../../commit/7c3e53c)
* add template name to render variables [89938ca](../../commit/89938ca)
* refactor cli [a24edbb](../../commit/a24edbb)
* fix bundler for multi-target dockerfile [5a8f7d0](../../commit/5a8f7d0)
* allow non-string types as values of context in ProjectMapping [26b410c](../../commit/26b410c)
* add script for testing simple liquid templates [c41609a](../../commit/c41609a)
* fix versioning task [3247e08](../../commit/3247e08)
* restore skip_secrets, modify TemplateHash to allow data structures as well as String (templates) [b1b5196](../../commit/b1b5196)
* README updates [5eccb20](../../commit/5eccb20)
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
