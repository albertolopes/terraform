variable "domain_name" {
  description = "Dominio base usado no ingress do pgAdmin."
  type        = string
  default     = ""
}

variable "pgadmin_hostname" {
  description = "Subdominio publico do pgAdmin."
  type        = string
  default     = "pgadmin"
}

variable "pgadmin_email" {
  description = "Email inicial de login do pgAdmin."
  type        = string
  default     = "admin@avocadotech.site"
}

variable "pgadmin_password" {
  description = "Senha inicial de login do pgAdmin."
  type        = string
  sensitive   = true
  default     = "pgadmin123"
}

variable "pgadmin_storage_size" {
  description = "Tamanho do volume persistente do pgAdmin."
  type        = string
  default     = "2Gi"
}

variable "pgadmin_enable_ingress" {
  description = "Habilita Ingress publico para o pgAdmin."
  type        = bool
  default     = true
}
