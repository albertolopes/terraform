# modules/gitlab/variables.tf

variable "domain_name" {
  description = "Domínio principal onde o GitLab será acessado"
  type        = string
}

variable "namespace" {
  description = "Namespace Kubernetes para instalar o GitLab"
  type        = string
  default     = "gitlab"
}

variable "root_password" {
  description = "Senha para o usuário root do GitLab"
  type        = string
  sensitive   = true
  default     = null
}