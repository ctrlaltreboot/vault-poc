#!/usr/bin/env bash
set -e

SCRIPT_DIR=$(dirname $0)
source "$SCRIPT_DIR"/shared.sh

#
#  AppRole
#
authn_enable_approle() {
  echo 'Enabling AppRole authentication'
  echo 'You can only do this once on the default path...'
  vault auth enable approle
  echo
}

echo 'Re-logging with the root token to enable AppRole'
echo 'Do this via: vault login <root-token-here>'
echo
autologin
echo
authn_enable_approle

# define variables for role names
# default is that there's an application admin and an application client
: ${APPROLE1:="admin"}
: ${APPROLE2:="client"}

# define directories and file paths for storage of approle outputs
APPROLE_DIR="$(pwd)/.approle"
[[ ! -e "$APPROLE_DIR" ]] && mkdir -pv "$APPROLE_DIR"

approle_create_role() {
  # this function takes the first argument and assigns it to a local variable ROLE
  local ROLE="$1"
  echo "Creating an application role $ROLE and defining attributes"
  vault write auth/approle/role/"$ROLE" \
    secret_id_ttl=10m \
    token_num_uses=3 \
    token_ttl=20m \
    token_max_ttl=30m \
    secret_id_num_uses=40
  echo
}

approle_fetch_ids() {
  local ROLE="$1"
  local ROLE_ID_FILE="$APPROLE_DIR/.$ROLE-role-id"
  echo "Fetching RoleID for $ROLE and storing the information into $ROLE_ID_FILE"
  # the fetched information is written both to stdout and a file using the tee ulititee
  vault read auth/approle/role/"$ROLE"/role-id | tee "$ROLE_ID_FILE"
  echo
  local SECRET_ID_FILE="$APPROLE_DIR/.$ROLE-secret-id"
  echo "Fetching SecretID for $ROLE and storing the information into $SECRET_ID_FILE"
  vault write -f auth/approle/role/"$ROLE"/secret-id | tee "$SECRET_ID_FILE"
  echo
}

# create the admin role first
approle_create_role "$APPROLE1"
sleep 3
# fetch the admin's secret and role id and save it to their respective files
approle_fetch_ids "$APPROLE1"
sleep 3

# create the client role next
approle_create_role "$APPROLE2"
sleep 3
# fetch the client's secret and role id and save it to their respective files
approle_fetch_ids "$APPROLE2"
