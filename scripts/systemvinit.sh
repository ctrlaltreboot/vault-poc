#!/usr/bin/env bash

# exit whenever any errors come up
set -e

SCRIPT_DIR=$(dirname $0)
source "$SCRIPT_DIR"/helpers.sh
source "$SCRIPT_DIR"/shared.sh


case $1 in
  "stop")
    stop_vault
    sleep 3
    ;;
  "start")
    start_vault
    sleep 3
    ;;
  "restart")
    stop_vault
    sleep 3
    start_vault
    sleep 3
    ;;
  *)
    echo "Usage: $0 start|stop|restart"
    exit 1
    ;;
esac
