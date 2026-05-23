# variables.tf (raiz do projeto)

variable "domain_name" {
  description = "Domínio principal"
  type        = string
  default     = "avocadotech.site" # Voltando para o domínio real
}

variable "admin_email" {
  description = "Email do administrador"
  type        = string
  default     = "albertolopes@mail.com"
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
  # ATENÇÃO: Se o seu Redis Alpine exige uma senha diferente,
  # mude aqui ou passe via terraform.tfvars.
  default = "gitlab-redis-password"
}

variable "postgres_password" {
  description = "Senha do banco PostgreSQL externo"
  type        = string
  sensitive   = true
  # ATENÇÃO: Coloque aqui a senha real que o seu PostgreSQL espera na porta 5433
  default = "postgres"
}

variable "gitlab_runner_token" {
  description = "GitLab Runner authentication token"
  type        = string
  sensitive   = true
  default     = "glrt-5e3ec77772cda317786173d3d0e157f7686a24be"
}

variable "tesseract_api_image" {
  description = "Imagem da API Tesseract ja disponivel no cluster ou registry"
  type        = string
  default     = "tesseract-api:latest"
}

variable "tesseract_ocr_image" {
  description = "Imagem do servico Tesseract OCR ja disponivel no cluster ou registry"
  type        = string
  default     = "tesseract-ocr:latest"
}

variable "tesseract_hostname" {
  description = "Subdominio publico da API Tesseract"
  type        = string
  default     = "tesseract"
}

variable "tesseract_api_build_context" {
  description = "Diretorio com o Dockerfile da API Tesseract para build/import local no k3d. Use null para nao buildar."
  type        = string
  default     = null
}

variable "tesseract_api_dockerfile" {
  description = "Dockerfile usado para build da API Tesseract. Use null para usar o Dockerfile do contexto."
  type        = string
  default     = null
}

variable "tesseract_ocr_build_context" {
  description = "Diretorio com o Dockerfile do Tesseract OCR para build/import local no k3d. Use null para nao buildar."
  type        = string
  default     = null
}

variable "tesseract_api_replicas" {
  description = "Quantidade de replicas da API Tesseract."
  type        = number
  default     = 1
}

variable "tesseract_enable_ingress" {
  description = "Habilita Certificate/Ingress publico para a API Tesseract."
  type        = bool
  default     = true
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
