source "https://rubygems.org"
gem "appmap"

# development dependencies
group :development do
  gem "rake"
  gem "pry"
  gem "pry-byebug"
end

# test dependencies
group :development, :test do
  gem "rspec"
  gem "vcr"
  gem "webmock"
  gem 'codecov', require: false, group: 'test'
  gem "simplecov"
end

# application runtime dependencies
gem 'gem_logger'
gem 'logging'
gem 'activesupport'
gem 'clamp'
gem 'cloudtruth-client', path: "client"
gem 'kubeclient'
gem 'liquid'
gem 'yaml-safe_load_stream', git: "https://github.com/wr0ngway/yaml-safe_load_stream.git", branch: "ruby_3"
gem 'async'
