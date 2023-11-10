source "https://rubygems.org"

# development dependencies
group :development do
  gem "rake"
  gem "pry"
  gem "pry-byebug"
  gem "ruby-debug-ide"
  gem "debase"
  gem "solargraph"
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
gem "activesupport"
gem "clamp"
gem "cloudtruth-client", path: "client"
gem "kubeclient"
gem "liquid"
gem "async"
gem "faraday-cookie_jar"
