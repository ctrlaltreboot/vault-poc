#!/usr/bin/env bash
set -e

#
# AppRole Login token
# In this phase we simulate getting a login token using curl.
# JSON responses are parsed by `jq` and should be installed
#

approle_set_login_file() {
  local ROLE="$1"
  local LOGIN_FILE="$APPROLE_DIR/.$ROLE-login.json"
  echo -n "$LOGIN_FILE"
}

approle_set_token_file() {
  local ROLE="$1"
  local TOKEN_FILE="$APPROLE_DIR/.$ROLE-token"
  echo -n "$TOKEN_FILE"
}

approle_login() {
  local ROLE=$1
  local ROLE_ID_FILE="$(approle_set_roleid_file $ROLE)"
  local SECRET_ID_FILE="$(approle_set_secretid_file $ROLE)"
  local LOGIN_FILE="$(approle_set_login_file $ROLE)"

  [[ ! -e "$ROLE_ID_FILE" ]] && exit
  ROLE_ID="$(tail -1 $ROLE_ID_FILE | awk '{print $2}' | xargs)"

  [[ ! -e "$SECRET_ID_FILE" ]] && exit
  SECRET_ID="$( tail -2 $SECRET_ID_FILE | head -1 | awk '{print $2}' | xargs)"

  # authentiction to vault using role
  echo 'Authenticating to vault using role_id and secret_id'
  curl -s \
    --request POST \
    --data '{"role_id":"'$ROLE_ID'","secret_id":"'$SECRET_ID'"}' \
    http://127.0.0.1:8200/v1/auth/approle/login &> "$LOGIN_FILE"
  cat "$LOGIN_FILE" | jq '.'
  echo
}

approle_set_login_token() {
  local ROLE=$1
  local LOGIN_FILE="$(approle_set_login_file $ROLE)"
  local TOKEN_FILE="$(approle_set_token_file $ROLE)"
  cat "$LOGIN_FILE" | jq '. | .auth.client_token' | xargs | tee $TOKEN_FILE
}

# secret ids have ttl, so we need to re-fetch the secret_id
# fetch admin secret id, log and save token
approle_fetch_secretid "$APPROLE1"
approle_login "$APPROLE1"
approle_set_login_token "$APPROLE1"
# fetch client secret id, log and save token
approle_fetch_secretid "$APPROLE2"
approle_login "$APPROLE2"
approle_set_login_token "$APPROLE2"
