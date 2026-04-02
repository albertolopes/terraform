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

output "traefik_loadbalancer_ip" {
  value = module.traefik.loadbalancer_ip
}

output "traefik_dashboard_url" {
  value = module.traefik.dashboard_url
}
