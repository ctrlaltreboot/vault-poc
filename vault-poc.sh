#!/usr/bin/env bash

# exit whenever any errors come up
set -e

# autounseal
: ${AUTO_UNSEAL:='no'}
# autologin
: ${AUTO_LOGIN:='no'}

# process id definition
PID_DIR=$(pwd)/pids
CONSUL_PID="$PID_DIR"/consul.pid
VAULT_PID="$PID_DIR"/vault.pid

# log directory definition
LOG_DIR=$(pwd)/logs

# policy directory definition
POLICY_DIR=$(pwd)/policies


# create directories if they're missing
[[ ! -e "$PID_DIR" ]] && mkdir -pv "$PID_DIR"
[[ ! -e "$LOG_DIR" ]] && mkdir -pv "$LOG_DIR"

# define where the operator initialization information
# would be saved unto...
SECRET=.operator.secret

#
# phase 1 is the initialization phase
#
start_consul_dev() {
  echo 'Starting Dev Consul Instance'
  # start a consule dev server
  # pushing all output to a log file
  # and writing the process id (represented by $!) into a file
  consul agent -dev &> "$LOG_DIR"/consul.dev.log & echo $! > "$CONSUL_PID"
}

start_vault() {
  echo 'Starting Vault Server'
  vault server -config=vaultconfig.hcl &> "$LOG_DIR"/vault.poc.log & echo $! > "$VAULT_PID"
}

init_vault() {
  echo 'Operator Initialization on Vault Server'
  # save all operation initialization information into a file
  vault operator init &> $SECRET
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
  echo 'Automatically login using the root token.'
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

login() {
  if [[ "$AUTO_LOGIN" == "yes" ]]; then
    echo 'AUTO_LOGIN is set to yes'
    autologin
  else
    login_message
  fi
}

phase1() {
  start_consul_dev
  sleep 2
  start_vault
  sleep 2
  export VAULT_ADDR='http://127.0.0.1:8200'
  init_vault
  sleep 3
  unseal
  login
}
# end of phase 1

#
# phase 2 is enabling github as authentication provider
# and defining the organization to identify/authenticate to
#
authn_enable_github() {
  echo 'Enable GitHub authentication'
  vault auth enable github
  echo
}

authn_define_github() {
  local ORG=${ORG:="hobodevops"}
  echo 'Write GitHub organization config'
  vault write auth/github/config organization=$ORG
  echo
}

phase2() {
  authn_enable_github
  authn_define_github
}
# end of phase 2

#
# phase 3 is when admin and n00b policies are written to vault
# and mapped out to their respective teams
#
authn_define_policy() {
  # this function checks a policy file and writes it into vault
  # assignment is done later
  local POLICY_NAME=$1
  local POLICY_FILE=$2
  # exit if the policy document is missing
  [[ ! -e "$POLICY_FILE" ]] && exit
  echo "Check and write the $POLICY_NAME policy"
  vault policy fmt "$POLICY_FILE"
  vault policy write "$POLICY_NAME" "$POLICY_FILE"
  echo
}

github_authn_map_policy() {
  # this function assigns a team's policy
  local TEAM_NAME=$1
  local POLICY_NAME=$1
  echo "Assign the $POLICY_NAME policy to the $TEAM_NAME team from the GitHub configured organization"
  vault write auth/github/map/teams/"$TEAM_NAME" value=default,"$POLICY_NAME"
  echo
}

phase3() {
  # set a new policy called admin-policy and assign the admin-policy.hcl document
  authn_define_policy admin-policy "$POLICY_DIR"/admin-policy.hcl
  # map the policy to the github team named "admin"
  github_authn_map_policy admin admin-policy

  # same goes for the n00bs
  authn_define_policy n00bs-policy "$POLICY_DIR"/n00bs-policy.hcl
  github_authn_map_policy n00bs n00bs-policy
}
# end of phase 3

#
# phase 4 - Try it out!
#
authn_github_login() {
  echo 'You must create a Github token before attempting to login'
  echo 'https://help.github.com/articles/creating-a-personal-access-token-for-the-command-line/'
  vault login -method=github
  echo
}

authz_write_secret() {
   echo 'Running this should work: `vault write secret/n00bs/am_i_a_n00b value=yes`'
   echo 'Runnng this should work: `vault list secret/n00bs`'
   echo
}

authz_write_fail() {
   echo 'Writing to restricted path would fail'
   echo 'Running this would fail: `vault write secret/supersecruds`'
   echo
}

phase4(){
  authn_github_login
  authz_write_secret
  authz_write_fail
}
# end of phase 4

#
# phase 5 - AppRole
#

# define variables for role names and files where roleid and secretid
# information will be saved

# admin
APPROLE_ADMIN_NAME="funapprolladmin"
# client
APPROLE_CLIENT_NAME="funapprollclient"

authn_enable_approle() {
  echo 'Enable AppRole authentication'
  vault auth enable approle
  echo
}

approle_create_role() {
  # this function takes the first argument and assigns it to a local variable ROLE_NAME
  local ROLE_NAME="$1"
  echo "Create an example application role: $ROLE_NAME"
  vault write auth/approle/role/"$ROLE_NAME" \
    secret_id_ttl=10m \
    token_num_uses=3 \
    token_ttl=20m \
    token_max_ttl=30m \
    secret_id_num_uses=40
  echo
}

approle_fetch_roleid() {
  # this function takes 2 arguments, the 1st assigned to a local variable ROLE_NAME
  # the 2nd assignment is for the file where the role-id information is saved
  local ROLE_NAME="$1"
  local ROLE_ID_FILE=".$ROLE_NAME.role_id"
  echo "Fetching RoleID: $ROLE_NAME"
  # the fetched information is written both to stdout and a file using the tee ulititee
  vault read auth/approle/role/"$ROLE_NAME"/role-id | tee "$ROLE_ID_FILE"
  echo
}

approle_fetch_secretid() {
  # this function takes 2 arguments, the 1st assigned to a local variable ROLE_NAME
  # the 2nd assignment is for the file where the secret-id information is saved
  local ROLE_NAME="$1"
  local SECRET_ID_FILE=".$ROLE_NAME.secret_id"
  echo "Fetching SecretID: $ROLE_NAME"
  vault write -f auth/approle/role/"$ROLE_NAME"/secret-id | tee "$SECRET_ID_FILE"
  echo
}

phase5() {
  echo 'Re-login w/ the root token to enable AppRole'
  echo 'vault login <root-token-here>'
  autologin
  authn_enable_approle
  # create the admin role first
  approle_create_role "$APPROLE_ADMIN_NAME"
  # fetch the admin's role-id and save it to a file
  approle_fetch_roleid "$APPROLE_ADMIN_NAME" "$APPROLE_ADMIN_ROLEID"
  # fetch the admin's secret-id and save it to a file
  approle_fetch_secretid "$APPROLE_ADMIN_NAME" "$APPROLE_ADMIN_SECRETID"
  # create the client role next
  approle_create_role "$APPROLE_CLIENT_NAME"
  # fetch the client's role-id and save it to a file
  approle_fetch_roleid "$APPROLE_CLIENT_NAME" "$APPROLE_CLIENT_ROLEID"
  # fetch the client's secret-id and save it to a file
  approle_fetch_secretid "$APPROLE_CLIENT_NAME" "$APPROLE_CLIENT_SECRETID"
}
# end of phase 5

#
# phase 6 - AppRole and Authorization
#

# update the funapproll role policies
approle_authn_assign_policy() {
  local APPROLE_NAME="$1"
  local POLICY_NAME="$2"
  echo "Updates the policies for the $APPROLE_NAME role"
  vault write auth/approle/role/"$APPROLE_NAME"/policies policies=default,"$POLICY_NAME"
  echo
}

# check the current list of polices for the funapproll role
approle_authn_check_policy() {
  local APPROLE_NAME="$1"
  echo "Read attributes of the $APPROLE_NAME, check if the policy list correctness"
  vault read auth/approle/role/"$APPROLE_NAME"
  echo
}

phase6() {
  # funrollapp policy files definition
  APPROLE_ADMIN_POLICY="$POLICY_DIR"/funapproll-admin.hcl
  APPROLE_CLIENT_POLICY="$POLICY_DIR"/funapproll-client.hcl

  # set admin policy, assign admin policy to admin role then check
  authn_define_policy "$APPROLE_ADMIN_NAME" "$APPROLE_ADMIN_POLICY"
  approle_authn_assign_policy "$APPROLE_ADMIN_NAME" "$APPROLE_ADMIN_POLICY"
  approle_authn_check_policy "$APPROLE_ADMIN_NAME"

  # do the client next
  authn_define_policy "$APPROLE_CLIENT_NAME" "$APPROLE_CLIENT_POLICY"
  approle_authn_assign_policy "$APPROLE_CLIENT_NAME" "$APPROLE_CLIENT_POLICY"
  approle_authn_check_policy "$APPROLE_CLIENT_NAME"
}

#
# phase 7 - AppRole Test
# In this phase we simulate an "app" by interacting w/ the vault API
# using curl. JSON responses are parsed by `jq` and should be installed
#
approle_login() {
  local ROLE_NAME=$1
  local ROLE_ID_FILE=".$ROLE_NAME.role_id"
  local SECRET_ID_FILE=".$ROLE_NAME.secret_id"
  local LOGIN_RESPONSE_FILE=".$ROLE_NAME-approle-login.json"

  [[ ! -e "$ROLE_ID_FILE" ]] && exit
  ROLE_ID="$(tail -1 $ROLE_ID_FILE | awk '{print $2}' | xargs)"

  [[ ! -e "$SECRET_ID_FILE" ]] && exit
  SECRET_ID="$( tail -2 $SECRET_ID_FILE | head -1 | awk '{print $2}' | xargs)"

  # authentiction to vault using role
  echo 'Authenticating to vault using role_id and secret_id'
  curl -s \
    --request POST \
    --data '{"role_id":"'$ROLE_ID'","secret_id":"'$SECRET_ID'"}' \
    http://127.0.0.1:8200/v1/auth/approle/login &> "$LOGIN_RESPONSE_FILE"
  cat "$LOGIN_RESPONSE_FILE" | jq '.'
  echo
}

approle_read_login() {
  local ROLE_NAME=$1
  local LOGIN_RESPONSE_FILE=".$ROLE_NAME-approle-login.json"
  local CLIENT_TOKEN_FILE==".$ROLE_NAME-approle.token"
  cat "$LOGIN_RESPONSE_FILE" | jq '. | .auth.client_token' | xargs | tee $CLIENT_TOKEN_FILE
}

phase7() {
  # secret ids have ttl, so we need to re-fetch the secret_id
  # fetch admin secret id, log and save token
  approle_fetch_secretid "$APPROLE_ADMIN_NAME" "$APPROLE_ADMIN_SECRETID"
  approle_login "$APPROLE_ADMIN_NAME"
  approle_read_login "$APPROLE_ADMIN_NAME"
  # fetch client secret id, log and save token
  approle_fetch_secretid "$APPROLE_CLIENT_NAME" "$APPROLE_CLIENT_SECRETID"
  approle_login "$APPROLE_CLIENT_NAME"
  approle_read_login "$APPROLE_CLIENT_NAME"
}


#
# helper functions
#
stop_consul_dev() {
  kill -9 $(cat "$CONSUL_PID")
  [[ -e "$CONSUL_PID" ]] && rm "$CONSUL_PID"
}

stop_vault() {
  kill -9 $(cat "$VAULT_PID")
  [[ -e "$VAULT_PID" ]] && rm "$VAULT_PID"
}

stop() {
  stop_vault
  stop_consul_dev
}

# decides what to run based on the command line
# argument passed to the script
case "$1" in
  stop)
    stop
    ;;
  phase1)
    phase1
    ;;
  phase2)
    phase2
    ;;
  phase3)
    phase3
    ;;
  phase4)
    phase4
    ;;
  phase5)
    phase5
    ;;
  phase6)
    phase6
    ;;
  phase7)
    phase7
    ;;
  *)
    echo $"Usage $0 {stop|phase1|phase2|phase3|phase4|phase5|phase6}"
    exit
    ;;
esac
