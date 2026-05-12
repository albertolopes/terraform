output "dashboard_url" {
  description = "Traefik dashboard URL"
  value       = var.enable_dashboard ? "https://traefik.${var.domain_name}" : null
}

output "namespace" {
  description = "Traefik namespace"
  value       = kubernetes_namespace_v1.traefik.metadata[0].name
}

output "service_cluster_ip" {
  description = "ClusterIP interno do Service do Traefik"
  value       = kubernetes_service_v1.traefik.spec[0].cluster_ip
}
