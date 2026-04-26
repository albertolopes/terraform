output "tunnel_id" {
  description = "O ID único do túnel criado na Cloudflare"
  value       = cloudflare_tunnel.k3d_tunnel.id
}

output "tunnel_token" {
  description = "O token de autenticação do túnel. Deve ser passado para o Deployment do cloudflared no K8s."
  value       = cloudflare_tunnel.k3d_tunnel.tunnel_token
  sensitive   = true
}

output "tunnel_cname_target" {
  description = "O endereço de destino para os registros CNAME (.cfargotunnel.com)"
  value       = "${cloudflare_tunnel.k3d_tunnel.id}.cfargotunnel.com"
}

output "exposed_urls" {
  description = "Lista das URLs públicas que foram configuradas na Vercel"
  value       = [for s in var.services : "https://${s.hostname}.${var.domain_name}"]
}

output "tunnel_secret_generated" {
  description = "A senha do túnel gerada pelo random_password (útil para backup)"
  value       = random_password.tunnel_secret.result
  sensitive   = true
}