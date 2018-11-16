# vaultaire
This is an attempt to capture the initial stages of learning and
operating HashiCorp Vault.

This is a practice interpretation of the
[getting started](https://www.vaultproject.io/intro/getting-started/install.html)
documentation done in a small script to help understand the first steps of
operation. It is highly suggested that you read the fine manual before
using this (or even using this at all).

This is highly developmental and in no way production material *wink*

Requirements
------------
- You need to install Vault
- You'd need to create a Github Organization with example
  teams that will be defined in authorization policies.
- You would have to also generate a GitHub
  [personal access token](https://help.github.com/articles/creating-a-personal-access-token-for-the-command-line).
  This is used in the authentication phase.

Usage
-----
The scripts directory consists of sectional secripts that is intended to be run at a somewhat
linear fashion, depending on purpose.

Scripts and possible workflows
------------------------------

### Server startup and initialization with `scripts/setup.sh`
- An instance of Vault is started
- Vault is operationally initialized
- The script simulates the unsealing of logging in of a root user into
  an unsealed vault.

### GitHub based authentication and authorization
- Authentication setup with `scripts/github-authn.sh`
    - Enables GitHub authentication
    - Configures the GitHub organization for authorization reference
- Define GitHub team based access policies with `scripts/github-policies.sh`
- Test user authorization with `scripts/github-authz.sh

### AppRole authentication and authorization
- Enable AppRole authentication method with `scripts/approle-authn.sh`
- Define AppRole roles and policies and  with `scripts/approle-authz.sh`
- Mimic application interaction with Vault+AppRole with `scripts/approle-token.sh`
