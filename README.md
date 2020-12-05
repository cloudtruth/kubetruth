[![Build Status](https://github.com/cloudtruth/kubetruth/workflows/CD/badge.svg)](https://github.com/cloudtruth/kubetruth/actions)
[![Coverage Status](https://coveralls.io/repos/github/cloudtruth/kubetruth/badge.svg?branch=master)](https://coveralls.io/github/cloudtruth/kubetruth?branch=master)

# Kubetruth

The CloudTruth integration for kubernetes that pushes parameter updates into kubernetes config maps and secrets

## Installation

```
helm install
```

```shell
gem install 'kubetruth'
```

And then execute:

    $ kubetruth --help


## Usage

TODO: Write usage instructions here

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/wr0ngway/kubetruth.

