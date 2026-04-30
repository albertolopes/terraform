# modules/gitlab/variables.tf

variable "namespace" {
  description = "Namespace onde o GitLab será instalado"
  type        = string
}

variable "domain_name" {
  description = "Domínio principal (ex: avocadotech.site)"
  type        = string
}

variable "chart_version" {
  description = "Versão do Chart do GitLab"
  type        = string
}

variable "redis_password" {
  description = "Senha para o Redis Alpine externo"
  type        = string
  sensitive   = true
}

variable "postgres_password" {
  description = "Senha para o PostgreSQL externo (porta 5433)"
  type        = string
  sensitive   = true
}

variable "minio_access_key" {
  description = "Access Key do MinIO"
  type        = string
}

variable "minio_secret_key" {
  description = "Secret Key do MinIO"
  type        = string
  sensitive   = true
}

variable "root_password" {
  description = "Senha inicial do usuário root"
  type        = string
  sensitive   = true
  default     = null
}

variable "runner_authentication_token" {
  description = "Token de autenticação do GitLab Runner"
  type        = string
  sensitive   = true
}

variable "trusted_proxies" {
  description = "Lista de IPs/CIDRs confiáveis para o GitLab (Traefik/Cloudflare)"
  type        = list(string)
  default     = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "127.0.0.1"]
}