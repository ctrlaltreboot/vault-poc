#!/usr/bin/env bash

# exit whenever any errors come up
set -e

# autounseal?
: ${AUTO_UNSEAL:='no'}
# autologin?
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
  which consul &> /dev/null
  local HAS_CONSUL=$?
  (("$HAS_CONSUL" > 0)) && echo "No consul binary found in $PATH" && exit

  echo 'Starting Dev Consul Instance'
  # start a consule dev server
  # pushing all output to a log file
  # and writing the process id (represented by $!) into a file
  consul agent -dev &> "$LOG_DIR"/consul.dev.log &

  local PID=$(pgrep consul)

  if [[ -z "$PID" ]]; then
    echo "Consul is not running. Aborting"
    exit
  else
    echo -n "$PID" > "$CONSUL_PID"
  fi
}

start_vault() {
  which vault &> /dev/null
  local HAS_VAULT=$?
  (("$HAS_VAULT" > 0)) && echo "No vault binary found in $PATH" && exit

  echo 'Starting Vault Server'
  vault server -config=vaultconfig.hcl &> "$LOG_DIR"/vault.poc.log &

  local PID=$(pgrep vault)

  if [[ -z "$PID" ]]; then
    echo "Vault is not running. Aborting"
    exit
  else
    echo -n "$PID" > "$VAULT_PID"
  fi
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

# github authentication related variables
: ${GITHUB_ORG:="hobodevops"}

authn_enable_github() {
  echo 'Enabling GitHub authentication'
  vault auth enable github
  echo
}

authn_define_github() {
  echo "Setting $GITHUB_ORG for GitHub authentication"
  vault write auth/github/config organization="$GITHUB_ORG"
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

# github team name variables w/ defaults
: ${GITHUB_TEAM_1:=product}
GITHUB_TEAM_1_POLICY="$GITHUB_TEAM_1"-policy
: ${GITHUB_TEAM_2:=support}
GITHUB_TEAM_2_POLICY="$GITHUB_TEAM_2"-policy

authn_write_team_policy() {
  local TEAM1="$1"
  local TEAM2="$2"
  local POLICY_FILE="$POLICY_DIR/$TEAM1-policy.hcl"

  echo "Writing policy file for $TEAM1 team to $POLICY_FILE"

cat << EOF > "$POLICY_FILE"
path "secret/$TEAM1/*" {
  capabilities = ["create", "read", "delete", "list", "update"]
}

path "secret/$TEAM2/shared" {
  capabilities = ["read", "list"]
}
EOF
}

authn_define_policy() {
  # this function checks a policy file and writes it into vault
  # assignment is done later
  local TEAM1=$1
  local TEAM2=$2
  local POLICY_FILE="$POLICY_DIR/$TEAM1-policy.hcl"

  # write the policy document
  authn_write_team_policy $TEAM1 $TEAM2
  # exit if the policy file is missing
  [[ ! -e "$POLICY_FILE" ]] && echo "$POLICY_FILE is non-existent, aborting" && exit
  vault policy fmt "$POLICY_FILE"
  vault policy write "$TEAM1" "$POLICY_FILE"
  echo
}

github_authn_map_policy() {
  # this function assigns a team's policy
  local TEAM=$1
  echo "Assign the $TEAM policy to the $TEAM team from the $GITHUB_ORG organization"
  vault write auth/github/map/teams/"$TEAM" value=default,"$TEAM"
  echo
}


phase3() {
  # set a new policy for $GITHUB_TEAM_1 and map that policy
  authn_define_policy "$GITHUB_TEAM_1" "$GITHUB_TEAM_2"
  github_authn_map_policy "$GITHUB_TEAM_1"

  # same goes for the team 2
  authn_define_policy "$GITHUB_TEAM_2" "$GITHUB_TEAM_1"
  github_authn_map_policy "$GITHUB_TEAM_2"
}
# end of phase 3

#
# phase 4 - Try it out!
#
authn_github_team() {
  local TEAM="$1"
  echo
  echo "Let's try logging in as a user that belongs to $TEAM"
  echo 'You must create a Github token before attempting to login'
  echo 'https://help.github.com/articles/creating-a-personal-access-token-for-the-command-line/'
  vault login -method=github
  echo
  echo "As a GitHub user that belongs to $TEAM: "
  echo 'Running this command should work: '
  echo "    vault write secret/$TEAM/$TEAM-secret value=for-$TEAM-members-only"
  echo
  echo 'Writing to restricted path would fail: '
  echo 'Running this would fail: '
  echo "    vault write secret/restricted-area/$TEAM-secret value=shhh"
  echo
}

phase4(){
  echo 'Exercise requirements: '
  echo 'Create two different GitHub users'
  echo "Assign one user to $GITHUB_TEAM_1 team and the other to $GITHUB_TEAM_2 team within the $GITHUB_ORG organization"
  authn_github_team "$GITHUB_TEAM_1"
}
# end of phase 4

#
# phase 5 - AppRole
#

# define variables for role names
# this time there's an application admin and an application client

# admin
APPROLE_ADMIN_NAME="app-admin"

# client
APPROLE_CLIENT_NAME="app-client"

authn_enable_approle() {
  echo 'Enabling AppRole authentication'
  vault auth enable approle
  echo
}

approle_create_role() {
  # this function takes the first argument and assigns it to a local variable ROLE_NAME
  local ROLE_NAME="$1"
  echo "Creating an application role $ROLE_NAME and defining attributes"
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
  echo "Fetching RoleID for $ROLE_NAME and storing the information into $ROLE_ID_FILE"
  # the fetched information is written both to stdout and a file using the tee ulititee
  vault read auth/approle/role/"$ROLE_NAME"/role-id | tee "$ROLE_ID_FILE"
  echo
}

approle_fetch_secretid() {
  # this function takes 2 arguments, the 1st assigned to a local variable ROLE_NAME
  # the 2nd assignment is for the file where the secret-id information is saved
  local ROLE_NAME="$1"
  local SECRET_ID_FILE=".$ROLE_NAME.secret_id"
  echo "Fetching SecretID for $ROLE_NAME and storing the information into $SECRET_ID_FILE"
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
  sleep 3
  # fetch the admin's role-id and save it to a file
  approle_fetch_roleid "$APPROLE_ADMIN_NAME"
  sleep 3
  # fetch the admin's secret-id and save it to a file
  approle_fetch_secretid "$APPROLE_ADMIN_NAME"
  sleep 3


  # create the client role next
  approle_create_role "$APPROLE_CLIENT_NAME"
  sleep 3
  # fetch the client's role-id and save it to a file
  approle_fetch_roleid "$APPROLE_CLIENT_NAME"
  sleep 3
  # fetch the client's secret-id and save it to a file
  approle_fetch_secretid "$APPROLE_CLIENT_NAME"
}
# end of phase 5

#
# phase 6 - AppRole and Authorization
#

# update the role policies
approle_authn_assign_policy() {
  local APPROLE_NAME="$1"
  local POLICY_NAME="$2"
  echo "Updates the policies for the $APPROLE_NAME role"
  vault write auth/approle/role/"$APPROLE_NAME"/policies policies=default,"$POLICY_NAME"
  echo
}

# check the current list of policies for the role
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

approle_set_login_token() {
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
  approle_set_login_token "$APPROLE_ADMIN_NAME"
  # fetch client secret id, log and save token
  approle_fetch_secretid "$APPROLE_CLIENT_NAME" "$APPROLE_CLIENT_SECRETID"
  approle_login "$APPROLE_CLIENT_NAME"
  approle_set_login_token "$APPROLE_CLIENT_NAME"
}


#
# helper functions
#
stop_consul_dev() {
  if [[ -e "$CONSUL_PID" ]]; then
    kill -9 $(cat "$CONSUL_PID")
    rm "$CONSUL_PID"
  fi
}

stop_vault() {
  if [[ -e "$VAULT_PID" ]]; then
    kill -9 $(cat "$VAULT_PID")
    rm "$VAULT_PID"
  fi
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
    echo $"Usage $0 {stop|phase1|phase2|phase3|phase4|phase5|phase6|phase7}"
    exit
    ;;
esac
