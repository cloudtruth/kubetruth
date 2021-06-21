source "https://rubygems.org"

# development dependencies
group :development do
  gem "rake", "~> 12.0"
  gem "pry"
  gem "pry-byebug"
end

# test dependencies
group :development, :test do
  gem "rspec", "~> 3.0"
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
gem 'graphql-client'
gem 'kubeclient'
gem 'liquid'
