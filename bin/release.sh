#!/usr/bin/env bash -e

if [[ $# != 1 ]]; then
  echo "usage: $(basename $0) version"
  exit 1
fi

root_dir=$(cd $(dirname $0)/.. && pwd)
cd $root_dir

version=$1

if [[ $(git diff --stat) != '' ]]; then
  echo "The git tree is dirty, a clean tree is required to release"
  exit 1
fi

current_branch=$(git branch --show-current)
default_branch="master"
if [[ "$current_branch" != "$default_branch" ]]; then
  echo "Can only release from the default branch"
  exit 1
fi

./bin/assign_version.sh $version
bundle
./bin/changelog $version

echo git ci -m\"Updated changelog\" .
echo git push
echo git tag -f \"v${version}\"
echo git push -f --tags
