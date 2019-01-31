#!/usr/bin/env bash

# exit whenever any errors come up
set -e

SCRIPT_DIR=$(dirname $0)
source "$SCRIPT_DIR"/helpers.sh
source "$SCRIPT_DIR"/shared.sh

# autounseal?
: ${AUTO_UNSEAL:='yes'}
# autologin?
: ${AUTO_LOGIN:='yes'}

# create directories if they're missing
[[ ! -e "$PID_DIR" ]] && mkdir -pv "$PID_DIR"
[[ ! -e "$LOG_DIR" ]] && mkdir -pv "$LOG_DIR"
[[ ! -e "$POLICY_DIR" ]] && mkdir -pv "$POLICY_DIR"


init_vault() {
  echo 'Operator initialization on Vault server'
  # save all operation initialization information into a file
  vault operator init &> "$LOG_DIR"/"$SECRET"
  cp "$LOG_DIR"/"$SECRET" "$SECRET"
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

unseal() {
  if [[ "$AUTO_UNSEAL" == "yes" ]]; then
    autounseal
  else
    unseal_message
  fi
}

stop_vault
sleep 3

start_vault
sleep 3

export VAULT_ADDR='http://127.0.0.1:8200'

if [[ -d $(pwd)/vault-storage ]]; then
  echo "Vault has already been initialized, skipping initialization"
else
  init_vault
fi

sleep 3
unseal

if [[ "$AUTO_LOGIN" == "yes" ]]; then
  echo 'AUTO_LOGIN is set to yes'
  autologin
else
  login_message
fi
