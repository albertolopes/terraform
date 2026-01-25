variable "domain_name" {
  description = "The base domain name for the services."
  type        = string
  default     = "moedabot.xyz"
}

variable "keycloak_admin_user" {
  description = "The admin username for Keycloak."
  type        = string
  default     = "admin"
}
