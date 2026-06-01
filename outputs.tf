output "traefik_dashboard_url" {
  value = module.traefik.dashboard_url
}

output "meu_album_postgres_host" {
  description = "Host publico esperado para acessar o PostgreSQL do meu-album."
  value       = var.domain_name
}

output "meu_album_postgres_port" {
  description = "Porta publica exposta pelo Traefik para o PostgreSQL do meu-album."
  value       = 5432
}

output "meu_album_postgres_database" {
  description = "Nome do banco PostgreSQL do meu-album."
  value       = module.postgres.meu_album_postgres_database
}

output "meu_album_postgres_user" {
  description = "Usuario PostgreSQL do meu-album."
  value       = module.postgres.meu_album_postgres_user
}

output "meu_album_postgres_password" {
  description = "Senha forte gerada para o usuario PostgreSQL do meu-album."
  value       = module.postgres.meu_album_postgres_password
  sensitive   = true
}

output "meu_album_postgres_url" {
  description = "Connection string PostgreSQL do meu-album."
  value       = "postgresql://${module.postgres.meu_album_postgres_user}:${urlencode(module.postgres.meu_album_postgres_password)}@${var.domain_name}:5432/${module.postgres.meu_album_postgres_database}"
  sensitive   = true
}

output "tesseract_api_url" {
  description = "URL publica da API Tesseract."
  value       = module.tesseract.api_url
}

output "uptime_kuma_url" {
  description = "URL publica do Uptime Kuma."
  value       = module.uptime_kuma.url
}
