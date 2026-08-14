output "namespace" {
  description = "Namespace do servico de e-mail."
  value       = kubernetes_namespace_v1.mail.metadata[0].name
}

output "mail_host" {
  description = "Hostname dos protocolos SMTP/IMAP/JMAP."
  value       = local.mail_host
}

output "webmail_url" {
  description = "URL publica do SnappyMail."
  value       = "https://${local.webmail_host}"
}

output "admin_url" {
  description = "URL publica de administracao do Stalwart."
  value       = "https://${local.admin_host}"
}

output "stalwart_service_name" {
  description = "Service Kubernetes do Stalwart."
  value       = "stalwart"
}
