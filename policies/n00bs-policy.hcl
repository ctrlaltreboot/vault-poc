path "secret/*" {
  capabilities = ["read", "list"]
}

path "secret/n00bs/*" {
  capabilities = ["read", "list", "create"]
}
