#
# helper functions
#

start_vault() {
  if ! $(has_command vault); then
    echo "No vault binary found in $PATH"
    exit
  fi

  echo 'Starting vault server...'
  vault server -config=vaultconfig.hcl &> "$LOG_DIR"/vault.poc.log &
  sleep 2

  local PID="$(get_pid vault)"
  if [[ -z "$PID" ]]; then
    echo "Vault PID not found. Startup might've failed..."
    exit
  fi
}

stop_vault() {
  local PID="$(get_pid vault)"
  if [[ -n "$PID" ]]; then
    kill -9 "$PID"
    SUX=$?
    if [[ "$SUX" == "0" ]];  then
      echo "Vault server has been stopped..."
    else
      echo "Nothing to stop. Vault server is not running..."
    fi
  else
    echo "Nothing to stop. Vault server is not running..."
  fi
}

has_command() {
  local CMD="$1"
  [[ -n "$(command -v "$CMD")" ]]
}

get_pid() {
  local CMD="$1"
  local PID_FILE=$PID_DIR/$CMD.pid

  if [[ -f $PID_FILE ]]; then
    local PID=$(cat $PID_FILE)
  else
    local PID=$(pgrep "$CMD")
  fi

  if [[ -z "$PID" ]]; then
    echo
  else
    echo -n "$PID"
  fi
}
