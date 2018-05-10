# vault-poc
This is an attempt to capture the initial stages of learning and
operating HashiCorp Vault.

This is a practice interpretation of the [getting
started](https://www.vaultproject.io/intro/getting-started/install.html)
documentation done in a small script to help understand the first steps of
operation. It is highly suggested that you read the fine manual before
using this (or even using this at all).

This is highly developmental and in no way production material *wink*

### Requirements
- You need to install Consul
- You need to install Vault
- You'd need to create a Github Organization with corresponding teams that
  will be defined authorization policies.
- The script here uses the `hobodevops` organization with policies defined
  for `admin` and `n00bs` teams that exist in said organization.
- You would have to also generate a GitHub [personal access
  token](https://help.github.com/articles/creating-a-personal-access-token-for-the-command-line)
  This is used un the authentication phase.

### Usage
After all the prerequisites have been created, run the script in phases.

```
./vault-poc.sh <phase>
```

#### Phase 1
This is the initialization phase where:
- A development instance of Consul started
- An instance of Vault is started
- Vault is operationally initialized

This phase also ends with instructions on how to manually unseal and
login with the initial root token
