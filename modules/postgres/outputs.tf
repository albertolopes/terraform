output "postgres_password_secret_data" {
  description = "The base64-encoded PostgreSQL password from the secret."
  value       = kubernetes_secret_v1.postgres_secret.data.POSTGRES_PASSWORD
}

output "meu_album_postgres_namespace" {
  description = "Namespace da instancia PostgreSQL exposta para o banco meu-album."
  value       = kubernetes_namespace_v1.postgres.metadata[0].name
}

output "meu_album_postgres_service_name" {
  description = "Service Kubernetes da instancia PostgreSQL exposta para o banco meu-album."
  value       = kubernetes_service_v1.meu_album_postgres.metadata[0].name
}

output "meu_album_postgres_database" {
  description = "Banco criado na instancia PostgreSQL exposta."
  value       = "meu-album"
}

output "meu_album_postgres_user" {
  description = "Usuario da instancia PostgreSQL exposta."
  value       = "meu_album"
}

output "meu_album_postgres_password" {
  description = "Senha forte gerada para o usuario exposto meu_album."
  value       = random_password.meu_album_password.result
  sensitive   = true
}
