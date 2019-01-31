# process id definition
PID_DIR=$(pwd)/pids
VAULT_PID="$PID_DIR"/vault.pid

# log directory definition
LOG_DIR=$(pwd)/logs

# policy directory definition
POLICY_DIR=$(pwd)/policies

# define where the operator initialization
# information would be saved to...
SECRET=.operator-init.secret

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

autologin() {
  set_secrets
  echo 'DANGER: Automatically logging in via the root token.'
  echo 'DO NOT DO THIS IN PRODUCTION'

  vault login "$ROOT_SECRET"
  echo
}

authn_write_policy() {
  # an entity in this case can be a github team, and approle role, etc...
  local ENTITY1="$1"
  local ENTITY2="$2"
  local POLICY_FILE="$POLICY_DIR/$ENTITY1-policy.hcl"

  echo "Writing policy file for $ENTITY1 to $POLICY_FILE"

cat << EOF > "$POLICY_FILE"
path "secret/$ENTITY1/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
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
  echo "Running: authn_write_policy $ENTITY1 $ENTITY2"
  authn_write_policy $ENTITY1 $ENTITY2

  # exit if the policy file is missing
  [[ ! -e "$POLICY_FILE" ]] && echo "$POLICY_FILE is non-existent, aborting" && exit

  echo "Running: vault policy fmt $POLICY_FILE"
  vault policy fmt "$POLICY_FILE"

  echo "Running: vault policy write $ENTITY1 $POLICY_FILE"
  vault policy write "$ENTITY1" "$POLICY_FILE"
  echo
}
