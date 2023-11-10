source "https://rubygems.org"

# development dependencies
group :development do
  gem "rake"
  gem "pry"
  gem "debug"
end

# test dependencies
group :development, :test do
  gem "rspec"
  gem "vcr"
  gem "webmock"
  gem "codecov", require: false, group: "test"
  gem "simplecov"
  gem "dotenv"
end

# application runtime dependencies
gem "gem_logger"
gem "logging"
gem 'sigdump'
gem "activesupport", '~> 7.0', '<= 7.0.8'
gem "clamp"
gem "cloudtruth-client", path: "client"
gem "kubeclient"
gem "liquid"
gem "async"
gem "faraday-cookie_jar"
