#!/usr/bin/env bash -e

mkdir -p tmp
cp -Rp kubetruth tmp/
cp -Rp helmv2 tmp/kubetruth
sed -i -e 's/apiVersion: v2/apiVersion: v1/' tmp/kubetruth/Chart.yaml
sed -i -e 's/version: \([0-9.]*\)/version: \1-helmv2/' tmp/kubetruth/Chart.yaml
