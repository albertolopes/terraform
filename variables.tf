variable "domain_name" {
  description = "The base domain name for the services."
  type        = string
  default     = "moedabot.xyz"
}

variable "cloudflare_email" {
  description = "The email address associated with the Cloudflare account."
  type        = string
  sensitive   = true
}

variable "cloudflare_api_key" {
  description = "The Global API Key for the Cloudflare account."
  type        = string
  sensitive   = true
}

# --- Usernames ---
variable "keycloak_admin_user" {
  description = "The admin username for Keycloak."
  type        = string
  default     = "admin"
}

variable "minio_access_key" {
  description = "The access key (username) for Minio."
  type        = string
  default     = "minioadmin"
}
