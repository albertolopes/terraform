output "postgres_password_secret_data" {
  description = "The base64-encoded PostgreSQL password from the secret."
  value       = kubernetes_secret_v1.postgres_secret.data.POSTGRES_PASSWORD
}
