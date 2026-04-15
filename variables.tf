# variables.tf (raiz do projeto)

variable "domain_name" {
  description = "Domínio principal"
  type        = string
  default     = "tail799250.ts.net"
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