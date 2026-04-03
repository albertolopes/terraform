output "minio_secret_key" {
  value     = random_password.minio_secret_key.result
  sensitive = true
}

output "authentik_pg_password" {
  value     = random_password.authentik_pg_pass.result
  sensitive = true
}

output "authentik_secret_key" {
  value     = random_password.authentik_secret_key.result
  sensitive = true
}

output "traefik_loadbalancer_ip" {
  value = module.traefik.loadbalancer_ip
}

output "traefik_dashboard_url" {
  value = module.traefik.dashboard_url
}
