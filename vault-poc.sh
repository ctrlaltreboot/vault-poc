#!/usr/bin/env bash

# exit whenever any errors come up
set -e

# autounseal?
: ${AUTO_UNSEAL:='no'}
# autologin?
: ${AUTO_LOGIN:='no'}

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

# define where the operator initialization information
# would be saved unto...
SECRET=.operator.secret

#
# phase 1 is the initialization phase
#
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

login() {
  if [[ "$AUTO_LOGIN" == "yes" ]]; then
    echo 'AUTO_LOGIN is set to yes'
    autologin
  else
    login_message
  fi
}

phase1() {
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
  echo
  echo 'Enabling GitHub authentication'
  echo 'You can only do this once on the default path...'
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

authn_write_policy() {
  # an entity in this case can be a github team, and approle role, etc...
  local ENTITY1="$1"
  local ENTITY2="$2"
  local POLICY_FILE="$POLICY_DIR/$ENTITY1-policy.hcl"

  echo "Writing policy file for $ENTITY1 to $POLICY_FILE"

cat << EOF > "$POLICY_FILE"
path "secret/$ENTITY1/*" {
  capabilities = ["create", "read", "delete", "list", "update"]
}

path "secret/$ENTITY2/shared" {
  capabilities = ["read", "list"]
}
EOF
}

authn_define_policy() {
  # this function checks a policy file and writes it into vault
  # assignment is done later
  local ENTITY1=$1
  local ENTITY2=$2
  local POLICY_FILE="$POLICY_DIR/$ENTITY1-policy.hcl"

  # write the policy document
  authn_write_policy $ENTITY1 $ENTITY2
  # exit if the policy file is missing
  [[ ! -e "$POLICY_FILE" ]] && echo "$POLICY_FILE is non-existent, aborting" && exit
  vault policy fmt "$POLICY_FILE"
  vault policy write "$ENTITY1" "$POLICY_FILE"
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
# phase 5 - Enable AppRole
#
authn_enable_approle() {
  echo 'Enabling AppRole authentication'
  echo 'You can only do this once on the default path...'
  vault auth enable approle
  echo
}

phase5() {
  echo 'Re-logging with the root token to enable AppRole'
  echo 'Do this via: vault login <root-token-here>'
  echo
  autologin
  echo
  authn_enable_approle
}
# end of phase 5

#
# phase 5 - Enable AppRole
#

# define variables for role names
# default is that there's an application admin and an application client
: ${APPROLE1:="app-admin"}
: ${APPROLE2:="app-client"}

# define directories and file paths for storage of approle outputs
APPROLE_DIR="$(pwd)/.approle"
[[ ! -e "$APPROLE_DIR" ]] && mkdir -pv "$APPROLE_DIR"

approle_set_roleid_file() {
  local ROLE="$1"
  local ROLE_ID_FILE="$APPROLE_DIR/.$ROLE-role-id"
  echo -n "$ROLE_ID_FILE"
}

approle_set_secretid_file() {
  local ROLE="$1"
  local SECRET_ID_FILE="$APPROLE_DIR/.$ROLE-secret-id"
  echo -n "$SECRET_ID_FILE"
}

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

approle_fetch_roleid() {
  # this function takes 2 arguments, the 1st assigned to a local variable ROLE
  # the 2nd assignment is for the file where the role-id information is saved
  local ROLE="$1"
  local ROLE_ID_FILE="$(approle_set_roleid_file $ROLE)"
  echo "Fetching RoleID for $ROLE and storing the information into $ROLE_ID_FILE"
  # the fetched information is written both to stdout and a file using the tee ulititee
  vault read auth/approle/role/"$ROLE"/role-id | tee "$ROLE_ID_FILE"
  echo
}

approle_fetch_secretid() {
  # this function takes 2 arguments, the 1st assigned to a local variable ROLE
  # the 2nd assignment is for the file where the secret-id information is saved
  local ROLE="$1"
  local SECRET_ID_FILE="$(approle_set_secretid_file $ROLE)"
  echo "Fetching SecretID for $ROLE and storing the information into $SECRET_ID_FILE"
  vault write -f auth/approle/role/"$ROLE"/secret-id | tee "$SECRET_ID_FILE"
  echo
}

phase6() {
  # create the admin role first
  approle_create_role "$APPROLE1"
  sleep 3
  # fetch the admin's role-id and save it to a file
  approle_fetch_roleid "$APPROLE1"
  sleep 3
  # fetch the admin's secret-id and save it to a file
  approle_fetch_secretid "$APPROLE1"
  sleep 3


  # create the client role next
  approle_create_role "$APPROLE2"
  sleep 3
  # fetch the client's role-id and save it to a file
  approle_fetch_roleid "$APPROLE2"
  sleep 3
  # fetch the client's secret-id and save it to a file
  approle_fetch_secretid "$APPROLE2"
}
# end of phase 6

#
# phase 7 - AppRole and Authorization
#

# update the role policies
approle_authn_assign_policy() {
  local ROLE="$1"
  echo "Updates the policies for the $ROLE role"
  vault write auth/approle/role/"$ROLE"/policies policies=default,"$ROLE"
  echo
}

# check the current list of policies for the role
approle_authn_check_policy() {
  local ROLE="$1"
  echo "Read attributes of the $ROLE, check if the policy list correctness"
  vault read auth/approle/role/"$ROLE"
  echo
}

phase7() {
  # policy files definition
  # use the same function in phase 3 to define polices for role1 and role2
  authn_define_policy "$APPROLE1" "$APPROLE2"

  # set admin policy, assign admin policy to admin role then check
  approle_authn_assign_policy "$APPROLE1"
  approle_authn_check_policy "$APPROLE1"

  # do the client next
  authn_define_policy "$APPROLE2" "$APPROLE3"
  approle_authn_assign_policy "$APPROLE2"
  approle_authn_check_policy "$APPROLE2"
}
# end of phase 7

#
# phase 8 - AppRole Login token
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

phase8() {
  # secret ids have ttl, so we need to re-fetch the secret_id
  # fetch admin secret id, log and save token
  approle_fetch_secretid "$APPROLE1"
  approle_login "$APPROLE1"
  approle_set_login_token "$APPROLE1"
  # fetch client secret id, log and save token
  approle_fetch_secretid "$APPROLE2"
  approle_login "$APPROLE2"
  approle_set_login_token "$APPROLE2"
}
# end of phase 8


#
# helper functions
#
stop_vault() {
  if [[ -e "$VAULT_PID" ]]; then
    kill -9 $(cat "$VAULT_PID")
    rm "$VAULT_PID"
  fi
}

stop() {
  stop_vault
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
  phase8)
    phase8
    ;;
  *)
    echo $"Usage $0 {stop|phase1|phase2|phase3|phase4|phase5|phase6|phase7|phase8}"
    exit
    ;;
esac
