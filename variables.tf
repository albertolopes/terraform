variable "domain_name" {
  description = "The base domain name for the services."
  type        = string
  default     = "avocadotech.site"
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
variable "cloudflare_api_token" {
  description = "The API Token for Cloudflare DNS-01 challenge."
  type        = string
  sensitive   = true
}
