output "keycloak_admin_password" {
  value     = random_password.keycloak_admin.result
  sensitive = true
}

output "postgres_password" {
  value     = random_password.postgres.result
  sensitive = true
}

output "minio_secret_key" {
  value     = random_password.minio_secret_key.result
  sensitive = true
}
