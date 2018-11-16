#!/usr/bin/env bash
set -e

SCRIPT_DIR=$(dirname $0)
source "$SCRIPT_DIR"/shared.sh

#
# AppRole and Authorization
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

# policy files definition
# use the same function in phase 3 to define polices for role1 and role2
authn_define_policy "$APPROLE1" "$APPROLE2"

# set admin policy, assign admin policy to admin role then check
approle_authn_assign_policy "$APPROLE1"
approle_authn_check_policy "$APPROLE1"

# do the client next
authn_define_policy "$APPROLE2" "$APPROLE1"
approle_authn_assign_policy "$APPROLE2"
approle_authn_check_policy "$APPROLE2"
