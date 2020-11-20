require_relative 'lib/kubetruth/version'

Gem::Specification.new do |spec|
  spec.name          = "kubetruth"
  spec.version       = Kubetruth::VERSION
  spec.authors       = ["Matt Conway"]
  spec.email         = ["matt@cloudtruth.com"]

  spec.summary       = %q{The CloudTruth integration for kubernetes}
  spec.description   = %q{The CloudTruth integration for kubernetes that pushes parameter updates into kubernetes config maps and secrets}
  spec.homepage      = "https://cloudtruth.com"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.3.0")

  spec.metadata["allowed_push_host"] = "http://rubygems.com"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/cloudtruth/kubetruth"
  spec.metadata["changelog_uri"] = "https://github.com/cloudtruth/kubetruth/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir['*.md', 'LICENSE', 'exe/**/*', 'lib/**/*']
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency 'gem_logger'
  spec.add_dependency 'logging'
  spec.add_dependency 'clamp'
  spec.add_dependency 'graphql-client'
  spec.add_dependency 'kubeclient'

end
