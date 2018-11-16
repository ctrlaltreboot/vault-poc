#!/usr/bin/env bash

set -e

SCRIPT_DIR=$(dirname $0)
source "$SCRIPT_DIR"/shared.sh

#
# github policies are written to vault
# and mapped out to their respective teams
#

# github team name variables w/ defaults
: ${GITHUB_TEAM_1:=product}
GITHUB_TEAM_1_POLICY="$GITHUB_TEAM_1"-policy
: ${GITHUB_TEAM_2:=support}
GITHUB_TEAM_2_POLICY="$GITHUB_TEAM_2"-policy

github_authn_map_policy() {
  # this function assigns a team's policy
  local TEAM=$1
  echo "Assign the $TEAM policy to the $TEAM team from the $GITHUB_ORG organization"
  echo "Running: vault write auth/github/map/teams/"$TEAM" value=default,$TEAM"
  vault write auth/github/map/teams/"$TEAM" value=default,"$TEAM"
  echo
}

# set a new policy for $GITHUB_TEAM_1 and map that policy
authn_define_policy "$GITHUB_TEAM_1" "$GITHUB_TEAM_2"
github_authn_map_policy "$GITHUB_TEAM_1"

# same goes for the team 2
authn_define_policy "$GITHUB_TEAM_2" "$GITHUB_TEAM_1"
github_authn_map_policy "$GITHUB_TEAM_2"
