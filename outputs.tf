output "traefik_dashboard_url" {
  value = module.traefik.dashboard_url
}

output "pgadmin_url" {
  description = "URL publica do pgAdmin."
  value       = module.postgres.pgadmin_url
}

output "pgadmin_email" {
  description = "Email inicial de login do pgAdmin."
  value       = module.postgres.pgadmin_email
}

output "postgres_admin_user" {
  description = "Usuario administrador para criar bancos via pgAdmin."
  value       = module.postgres.postgres_admin_user
}

output "postgres_admin_password" {
  description = "Senha do usuario administrador para criar bancos via pgAdmin."
  value       = module.postgres.postgres_admin_password
  sensitive   = true
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

output "backup_mount_point" {
  description = "Ponto de montagem configurado para o disco de backup."
  value       = var.backup_mount_point
}

output "gitlab_backup_host_path" {
  description = "Diretorio local onde o CronJob copia os backups finais do GitLab."
  value       = var.gitlab_backup_host_path
}

output "gitlab_backup_cronjob_name" {
  description = "Nome do CronJob customizado de backup do GitLab."
  value       = kubernetes_cron_job_v1.gitlab_backup.metadata[0].name
}

output "gitlab_backup_cleanup_cronjob_name" {
  description = "Nome do CronJob de limpeza de backups antigos do GitLab."
  value       = kubernetes_cron_job_v1.gitlab_backup_cleanup.metadata[0].name
}
