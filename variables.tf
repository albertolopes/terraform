# variables.tf (raiz do projeto)

variable "domain_name" {
  description = "Domínio principal"
  type        = string
  default     = "avocadotech.site" # Voltando para o domínio real
}

variable "admin_email" {
  description = "Email do administrador"
  type        = string
  default     = "admin@example.com"
}

variable "gitlab_root_password" {
  description = "Senha inicial do root do GitLab"
  type        = string
  sensitive   = true
  default     = "changeme123"
}

variable "minio_access_key" {
  description = "Access key do MinIO"
  type        = string
  default     = "minioadmin"
}

variable "minio_secret_key" {
  description = "Secret key do MinIO"
  type        = string
  sensitive   = true
  default     = "minioadmin123"
}

variable "redis_password" {
  description = "Redis password for GitLab"
  type        = string
  sensitive   = true
  default     = "gitlab-redis-password"
}

variable "gitlab_runner_token" {
  description = "GitLab Runner authentication token"
  type        = string
  sensitive   = true
  default     = "glrt-5e3ec77772cda317786173d3d0e157f7686a24be"
}

variable "cloudflare_api_token" {
  description = "Cloudflare API Token"
  type        = string
  sensitive   = true
}

variable "cloudflare_account_id" {
  description = "Cloudflare Account ID"
  type        = string
}

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID"
  type        = string
}
