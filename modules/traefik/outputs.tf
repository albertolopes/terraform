# Outputs básicos
output "loadbalancer_ip" {
  description = "LoadBalancer external IP"
  value       = try(kubernetes_service_v1.traefik.status[0].load_balancer[0].ingress[0].ip, "pending")
}

output "dashboard_url" {
  description = "Traefik dashboard URL"
  value       = var.enable_dashboard ? "https://traefik.${var.domain_name}" : null
}

output "namespace" {
  description = "Traefik namespace"
  value       = kubernetes_namespace_v1.traefik.metadata[0].name
}