#!/usr/bin/env bash

set -e
root_dir=$(cd $(dirname $0)/.. && pwd)
helmv2dir="${root_dir}/tmp/helmv2"

mkdir -p "${helmv2dir}"
cp -Rp "${root_dir}/helm/kubetruth" "${helmv2dir}/"
cp -Rp "${root_dir}/helm/helmv2"/* "${helmv2dir}/kubetruth/"
sed -i'' -e 's/apiVersion: v2/apiVersion: v1/' "${helmv2dir}/kubetruth/Chart.yaml"
sed -i'' -e 's/version: \([0-9.]*\)/version: \1-helmv2/' "${helmv2dir}/kubetruth/Chart.yaml"
