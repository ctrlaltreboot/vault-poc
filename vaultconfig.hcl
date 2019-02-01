storage "file" {
  path = "vault-storage/"
}

listener "tcp" {
  address     = "127.0.0.1:8200"

  # uncomment if you don't have certs
  # tls_disable = 1

  # comment if you don't have certs
  #
  tls_cert_file = "./certs/vaultaire.local.crt.pem"
  tls_key_file  = "./certs/vaultaire.local.pk.pem"
}

# uncomment if you encounter the mlock error when starting vault
disable_mlock = true
pid_file = "pids/vault.pid"
