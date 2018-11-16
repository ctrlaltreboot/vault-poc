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
