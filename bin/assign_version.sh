#!/usr/bin/env bash -e

if [[ $# != 1 ]]; then
  echo "usage: $(basename $0) version"
  exit 1
fi

root_dir=$(cd $(dirname $0)/.. && pwd)
tag=$1

sed -i '' -e "s/^version:.*/version: $tag/" "${root_dir}/helm/kubetruth/Chart.yaml"
sed -i '' -e "s/^appVersion:.*/appVersion: $tag/" "${root_dir}/helm/kubetruth/Chart.yaml"
sed -i '' -e "s/VERSION *=.*/VERSION = \"$tag\"/" "${root_dir}/lib/kubetruth/version.rb"
