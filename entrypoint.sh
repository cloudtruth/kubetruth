#!/usr/bin/env bash

# fail fast
set -e

action=$1; shift

case $action in

  app)
  echo "Starting app"
  exec bundle exec kubetruth "$@"
  ;;

  console)
    echo "Starting console"
    exec bundle exec rake console
  ;;

  test)
    echo "Starting tests"
    exec bundle exec rspec
  ;;

  bash)
    if [ "$#" -eq 0 ]; then
      bash_args=( -i )
    else
      bash_args=( "$@" )
    fi
    exec bash "${bash_args[@]}"
  ;;

  exec)
    exec "$@"
  ;;

  *)
    echo "Unknown action: '$action', defaulting to exec"
    exec $action "$@"
  ;;

esac
