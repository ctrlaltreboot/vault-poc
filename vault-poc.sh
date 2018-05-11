#!/usr/bin/env bash

# exit whenever any errors come up
set -e

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

#
# phase 1 is the initialization phase
#
start_consul_dev() {
  echo 'Starting Dev Consul Instance'
  consul agent -dev &> $LOGDIR/consul.dev.log & echo $! > $CONSULPID
}

start_vault() {
  echo 'Starting Vault Server'
  vault server -config=vaultconfig.hcl &> $LOGDIR/vault.poc.log & echo $! > $VAULTPID
}

init_vault() {
  echo 'Operator Initialization on Vault Server'
  vault operator init &> operator_init.secret
}

unseal_message() {
  echo 'After operator initilization, you need to unseal the vault 3 times'
  echo 'Run `export VAULT_ADDR="http://127.0.0.1:8200"`'
  echo 'Run `vault operator unseal`'
  echo 'When unsealed, initial login will be via the `root` token'
  echo 'Run `vault login <root-token>`'
}

phase1() {
  start_consul_dev
  sleep 1
  start_vault
  sleep 1
  export VAULT_ADDR='http://127.0.0.1:8200'
  init_vault
  sleep 1
  unseal_message
}
#
# end of phase 1
#

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
#
# end of phase 2
#

#
# phase 3 is when admin and n00b policies are written to vault
# and mapped out to their respective teams
#
authn_define_policy_admin_team() {
  # exit if the admin policy document is missing
  [[ ! -e $ADMINPOLICY ]] && exit
  vault policy fmt $ADMINPOLICY
  vault policy write admin-policy $ADMINPOLICY
}

authn_define_policy_admin_n00bs() {
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
#
# end of phase 3
#

#
# phase 4 -try it out!
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
  *)
    echo $"Usage $0 {stop|phase1|phase2|phase3|phase4}"
    exit
    ;;
esac
