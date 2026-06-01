output "namespace" {
  description = "Namespace Kubernetes do Uptime Kuma."
  value       = kubernetes_namespace_v1.uptime_kuma.metadata[0].name
}

output "service_name" {
  description = "Nome do Service do Uptime Kuma."
  value       = kubernetes_service_v1.uptime_kuma.metadata[0].name
}

output "url" {
  description = "URL publica do Uptime Kuma."
  value       = "https://${local.public_host}"
}
