#!/usr/bin/env bash

# exit whenever any errors come up
set -e

# autounseal
: ${AUTOUNSEAL:='no'}
# autologin
: ${AUTOLOGIN:='no'}

# process id definition
PIDDIR=$(pwd)/pids
CONSULPID=$PIDDIR/consul.pid
VAULTPID=$PIDDIR/vault.pid

# log directory definition
LOGDIR=$(pwd)/logs

# policy directory definition
POLICYDIR=$(pwd)/policies

# policy files definition
ADMINPOLICY=$POLICYDIR/admin-policy.hcl
N00BSPOLICY=$POLICYDIR/n00bs-policy.hcl

# create directories if they're missing
[[ ! -e $PIDDIR ]] && mkdir -pv $PIDDIR
[[ ! -e $LOGDIR ]] && mkdir -pv $LOGDIR

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
  consul agent -dev &> $LOGDIR/consul.dev.log & echo $! > $CONSULPID
}

start_vault() {
  echo 'Starting Vault Server'
  vault server -config=vaultconfig.hcl &> $LOGDIR/vault.poc.log & echo $! > $VAULTPID
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
    SECRET1=$(head -7 $SECRET | head -1 | awk '{print $4}' | xargs)
    SECRET2=$(head -7 $SECRET | head -2 | tail -1 | awk '{print $4}' | xargs)
    SECRET3=$(head -7 $SECRET | head -3 | tail -1 | awk '{print $4}' | xargs)
    SECRET4=$(head -7 $SECRET | head -4 | tail -1 | awk '{print $4}' | xargs)
    SECRET5=$(head -7 $SECRET | head -5 | tail -1 | awk '{print $4}' | xargs)
    ROOTSECRET=$(head -7 $SECRET | tail -1 | awk '{print $4}' | xargs)
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
  vault operator unseal "$SECRET1"
  echo
  echo 'Second Unseal Attempt...'
  vault operator unseal "$SECRET3"
  echo
  echo 'Final Unseal Attempt...'
  vault operator unseal "$SECRET5"
  echo
}

autologin() {
  set_secrets
  echo 'Automatically login using the root token.'
  echo 'DO NOT DO THIS IN PRODUCTION'
  vault login "$ROOTSECRET"
  echo
}

unseal() {
  if [[ "$AUTOUNSEAL" == "yes" ]]; then
    autounseal
  else
    unseal_message
  fi
}

login() {
  if [[ "$AUTOLOGIN" == "yes" ]]; then
    echo 'AUTOLOGIN is set to yes'
    autologin
  else
    login_message
  fi
}

phase1() {
  start_consul_dev
  sleep 1
  start_vault
  sleep 1
  export VAULT_ADDR='http://127.0.0.1:8200'
  init_vault
  sleep 2
  unseal
  login
}
# end of phase 1

#
# phase 2 is enabling github as authentication provider
# and defining the organization to identify/authenticate to
#
authn_enable_github() {
  vault auth enable github
}

authn_define_github() {
  local ORG=${ORG:="hobodevops"}
  vault write auth/github/config organization=$ORG
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

authn_define_policy_admin_team() {
  # exit if the policy document is missing
  [[ ! -e $ADMINPOLICY ]] && exit
  vault policy fmt $ADMINPOLICY
  vault policy write admin-policy $ADMINPOLICY
}

authn_define_policy_admin_n00bs() {
  # exit if the policy document is missing
  [[ ! -e $N00BSPOLICY ]] && exit
  vault policy fmt $N00BSPOLICY
  vault policy write n00bs-policy $N00BSPOLICY
}

authn_map_admin_policy() {
  vault write auth/github/map/teams/admin value=default,admin-policy
}

authn_map_n00bs_policy() {
  vault write auth/github/map/teams/n00bs value=default,n00bs-policy
}

phase3() {
  authn_define_policy_admin_team
  authn_define_policy_admin_n00bs
  authn_map_admin_policy
  authn_map_n00bs_policy
}
# end of phase 3

#
# phase 4 - Try it out!
#
authn_github_login() {
  echo 'You must create a Github token before attempting to login'
  echo 'https://help.github.com/articles/creating-a-personal-access-token-for-the-command-line/'
  vault login -method=github
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
authn_enable_approle() {
  echo 'Enable AppRole authentication'
  vault auth enable approle
  echo
}

approle_create_role() {
  echo 'Create and example role, funapproll'
  vault write auth/approle/role/funapproll \
    secret_id_ttl=10m \
    token_num_uses=10 \
    token_ttl=20m \
    token_max_ttl=30m \
    secret_id_num_uses=40
  echo
}

approle_fetch_roleid() {
  echo 'Fetch the RoleID for funapproll'
  # the fetched information is written both to stdout and a file using the tee ulititee
  vault read auth/approle/role/funapproll/role-id | tee .funapproll.roleid
  echo
}

approle_fetch_secretid() {
  echo 'Fetch the SecretID for funapproll'
  vault write -f auth/approle/role/funapproll/secret-id | tee .funapproll.secretid
  echo
}

phase5() {
  echo 'Need to re-login w/ the root token to enable AppRole'
  echo 'vault login <root-token-here>'
  autologin
  authn_enable_approle
  approle_create_role
  approle_fetch_roleid
  approle_fetch_secretid
}
# end of phase 5

#
# phase 6 - AppRole and Authorization
#

# funrollapp policy files definition
FUNAPPROLLADMINPOLICY=$POLICYDIR/funapproll-admin.hcl
FUNAPPROLLCLIENTPOLICY=$POLICYDIR/funapproll-client.hcl

# check and write the funapproll polices into vault
authn_define_policy_funapproll_admin() {
  # exit if the policy document is missing
  [[ ! -e $FUNAPPROLLADMINPOLICY ]] && exit
  vault policy fmt $FUNAPPROLLADMINPOLICY
  vault policy write funapprolladmin-policy $FUNAPPROLLADMINPOLICY
}

authn_define_policy_funapproll_client() {
  # exit if the policy document is missing
  [[ ! -e $FUNAPPROLLCLIENTPOLICY ]] && exit
  vault policy fmt $FUNAPPROLLCLIENTPOLICY
  vault policy write funapprollclient-policy $FUNAPPROLLCLIENTPOLICY
}

# update the funapproll role policies
authn_update_funapproll_policy() {
  vault write auth/approle/role/funapproll/policies policies=default,funapprolladmin-policy,funapprollclient-policy
}

# check the current list of polices for the funapproll role
authn_check_funapproll_policy() {
  vault list auth/approle/role/funapproll/policies
}

phase6() {
  authn_define_policy_funapproll_admin
  authn_define_policy_funapproll_client
  authn_update_funapproll_policy
  authn_check_funapproll_policy
}

#
# helper functions
#
stop_consul_dev() {
  kill -9 $(cat $CONSULPID)
  [[ -e $CONSULPID ]] && rm $CONSULPID
}

stop_vault() {
  kill -9 $(cat $VAULTPID)
  [[ -e $VAULTPID ]] && rm $VAULTPID
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
  *)
    echo $"Usage $0 {stop|phase1|phase2|phase3|phase4|phase5|phase6}"
    exit
    ;;
esac
