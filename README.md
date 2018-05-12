# vault-poc
This is an attempt to capture the initial stages of learning and
operating HashiCorp Vault.

This is a practice interpretation of the [getting
started](https://www.vaultproject.io/intro/getting-started/install.html)
documentation done in a small script to help understand the first steps of
operation. It is highly suggested that you read the fine manual before
using this (or even using this at all).

This is highly developmental and in no way production material *wink*

Requirements
------------
- You need to install Consul
- You need to install Vault
- You'd need to create a Github Organization with corresponding teams that
  will be defined authorization policies.
- The script here uses the `hobodevops` organization with policies defined
  for `admin` and `n00bs` teams that exist in said organization.
- You would have to also generate a GitHub [personal access
  token](https://help.github.com/articles/creating-a-personal-access-token-for-the-command-line)
  This is used un the authentication phase.

Usage
-----
After all the prerequisites have been created, run the script in phases.

```
./vault-poc.sh <phase>
```

### Phase 1
#### Server Startup and Initialization
- A development instance of Consul started
- An instance of Vault is started
- Vault is operationally initialized
- This phase ends with either instructions on how to manually unseal
  and  login with the initial root token displayed or auto-unsealing
  and auto-login w/ the root token. These are determined by the
  environment variables `AUTOUNSEAL (default 'no')` and `AUTOLOGIN
  (default 'no')`

### Phase 2
#### GitHub Authentication
This is the authentication method enabling phase.
- Enables GitHub authentication
- Configures the organization in Github for authorization reference

### Phase 3
#### Policies and Authorization
- Check and verify policies
- Add and assign policies, mapped into
  their corresponding GitHub teams

### Phase 4
#### GitHub authentication practice
- Trying out the GitHub authentication by logging in and trying
out the commands echoed out

### Phase 5
#### AppRole
- Enable AppRole authentication method
- Create an example role
- Fetch and show RoleID
- Fetch and show SecretID

### Phase 6
#### AppRole Policy
- Create and write new polices
- Attach new policies to example role created in phase5
- Verify role and policies

