#!/usr/bin/env bash

# fail fast
set -e

action=$1; shift

case $action in

  app)
  echo "Starting app"
  exec kubetruth "$@"
  ;;

  console)
    echo "Starting console"
    exec rake console
  ;;

  test)
    echo "Starting tests"
    exec rspec
  ;;

  bash)
    if [ "$#" -eq 0 ]; then
      bash_args=( -i )
    else
      bash_args=( "$@" )
    fi
    exec bash "${bash_args[@]}"
  ;;

  *)
    exec $action "$@"
  ;;

esac
