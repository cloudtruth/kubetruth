#!/usr/bin/env bash

# fail fast
set -e

function start_app {
  echo "Starting app"

  exec kubetruth "$@"
}
export -f start_app

function start_console {
  echo "Starting console"
  exec bundle exec irb
}
export -f start_console

action=$1; shift

case $action in

  app)
    start_app "$@"
  ;;

  console)
    start_console
  ;;

  test)
    echo "Starting tests"
    exec bundle exec rspec
  ;;

  bash)
    if [ "$#" -eq 0 ]; then
      bash_args=( -il )
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
