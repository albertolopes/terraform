output "keycloak_admin_password" {
  value     = random_password.keycloak_admin.result
  sensitive = true
}

output "postgres_password" {
  value     = random_password.postgres.result
  sensitive = true
}
