#!/usr/bin/env bash

# exit whenever any errors come up
set -e

SCRIPT_DIR=$(dirname $0)
source "$SCRIPT_DIR"/helpers.sh

# autounseal?
: ${AUTO_UNSEAL:='yes'}
# autologin?
: ${AUTO_LOGIN:='yes'}

# process id definition
PID_DIR=$(pwd)/pids
VAULT_PID="$PID_DIR"/vault.pid

# log directory definition
LOG_DIR=$(pwd)/logs

# policy directory definition
POLICY_DIR=$(pwd)/policies

# create directories if they're missing
[[ ! -e "$PID_DIR" ]] && mkdir -pv "$PID_DIR"
[[ ! -e "$LOG_DIR" ]] && mkdir -pv "$LOG_DIR"
[[ ! -e "$POLICY_DIR" ]] && mkdir -pv "$POLICY_DIR"

# define where the operator initialization
# information would be saved to...
SECRET=.operator-init.secret

init_vault() {
  echo 'Operator Initialization on Vault Server'
  # save all operation initialization information into a file
  vault operator init &> "$LOG_DIR"/"$SECRET"
  cp "$LOG_DIR"/"$SECRET" "$SECRET"
}

set_secrets() {
  # this function reads the saved operator initialization information
  # the information is then parsed and saved into variable corresponding
  # to the 5 unseal keys and the root token
  if [[ -e $SECRET ]] && [[ -s $SECRET ]]; then
    UNSEAL1=$(head -7 $SECRET | head -1 | awk '{print $4}' | xargs)
    UNSEAL2=$(head -7 $SECRET | head -2 | tail -1 | awk '{print $4}' | xargs)
    UNSEAL3=$(head -7 $SECRET | head -3 | tail -1 | awk '{print $4}' | xargs)
    UNSEAL4=$(head -7 $SECRET | head -4 | tail -1 | awk '{print $4}' | xargs)
    UNSEAL5=$(head -7 $SECRET | head -5 | tail -1 | awk '{print $4}' | xargs)
    ROOT_SECRET=$(head -7 $SECRET | tail -1 | awk '{print $4}' | xargs)
  fi
}

unseal_message() {
  echo 'After operator initilization, you need to unseal the vault 3 times'
  echo 'Run `export VAULT_ADDR="http://127.0.0.1:8200"`'
  echo 'Run `vault operator unseal`'
}

login_message() {
  echo 'When unsealed, initial login will be via the `root` token'
  echo 'Run `vault login <root-token>`'
}

autounseal() {
  set_secrets
  echo 'After operator initilization, you need to unseal the vault 3 times'
  echo 'AUTOUNSEAL is set to yes, automatically unsealing. DO NOT DO THIS IN PRODUCTION'
  echo 'First Unseal Attempt...'
  vault operator unseal "$UNSEAL1"
  echo
  echo 'Second Unseal Attempt...'
  vault operator unseal "$UNSEAL3"
  echo
  echo 'Final Unseal Attempt...'
  vault operator unseal "$UNSEAL5"
  echo
}

autologin() {
  set_secrets
  echo 'DANGER: Automatically logging in via the root token.'
  echo 'DO NOT DO THIS IN PRODUCTION'
  vault login "$ROOT_SECRET"
  echo
}

unseal() {
  if [[ "$AUTO_UNSEAL" == "yes" ]]; then
    autounseal
  else
    unseal_message
  fi
}

start_vault
sleep 2
export VAULT_ADDR='http://127.0.0.1:8200'
init_vault
sleep 3
unseal

if [[ "$AUTO_LOGIN" == "yes" ]]; then
  echo 'AUTO_LOGIN is set to yes'
  autologin
else
  login_message
fi
