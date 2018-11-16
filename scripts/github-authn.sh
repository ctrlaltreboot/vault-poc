#!/usr/bin/env bash

set -e

#
# enabling github as authentication provider
# and defining the organization to identify/authenticate to
#

# github authentication related variables
: ${GITHUB_ORG:="hobodevops"}

# authn enable github
echo
echo 'Enabling GitHub authentication'
echo 'You can only do this once on the default path...'
echo 'Running: vault auth enable github'
vault auth enable github
echo

# authn_define_github
echo "Setting $GITHUB_ORG for GitHub authentication"
echo "Running: vault write auth/github/config organization=$GITHUB_ORG"
vault write auth/github/config organization="$GITHUB_ORG"
echo
