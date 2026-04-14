output "dashboard_url" {
  description = "Traefik dashboard URL"
  value       = var.enable_dashboard ? "https://traefik.${var.domain_name}" : null
}

output "namespace" {
  description = "Traefik namespace"
  value       = kubernetes_namespace_v1.traefik.metadata[0].name
}