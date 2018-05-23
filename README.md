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
- You need to install Vault
- You'd need to create a Github Organization with example
  teams that will be defined in authorization policies.
- You would have to also generate a GitHub [personal access
  token](https://help.github.com/articles/creating-a-personal-access-token-for-the-command-line).
  This is used in the authentication phase.

Application Defaults
--------------------
The script is riddled with values that can be overriden by setting
specific environment variable which makes it easy for the script to
conform to your preferences.

|Variable|Description|Default|
|--------|-----------|-------|
|`GITHUB_ORG`|Github Organization|`hobodevops`|

Usage
-----
The script is intended to be run at a linear fashion in what's called
phases. A particular phase would describe a vault operation scenario.

```
./vault-poc.sh <phase>
```

Phases
------

### Phase 1: Server Startup and Initialization
- An instance of Vault is started
- Vault is operationally initialized
- This phase ends with either instructions on how to manually unseal
  and  login with the initial root token displayed or auto-unsealing
  and auto-login w/ the root token. These are determined by the
  environment variables `AUTOUNSEAL (default 'no')` and `AUTOLOGIN
  (default 'no')`

### Phase 2: GitHub Authentication
This is the authentication method enabling phase.
- Enables GitHub authentication
- Configures the organization in Github for authorization reference

### Phase 3: Policies and Authorization
- Generate, check and verify vault policies
  for GitHub teams
- Add and assign policies, mapped into
  their corresponding GitHub teams

### Phase 4: GitHub authentication practice
- Trying out the GitHub authentication by logging using a GitHub
  personal token in and trying out the commands echoed out
- You're free to try out any other commands at this stage as vault is
  already operational

### Phase 5: Enable AppRole
- Enable AppRole authentication method

### Phase 6: AppRole Role Management
- Create an example role
- Fetch and show RoleID
- Fetch and show SecretID

### Phase 7:  AppRole Policy
- Create and write new polices for AppRole roles
- Attach new policies to an example role created in phase 5
- Verify the newly created role and its attributes and if it has our pre-defined policy attached to it

### Phase 8:  AppRole Login Token
- Interact with Vault via `curl` and parse the JSON outputs via `jq`
- Mimic an application fetching a login token

