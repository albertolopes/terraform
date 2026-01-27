variable "domain_name" {
  description = "The base domain name for the services."
  type        = string
  default     = "moedabot.xyz"
}

variable "cloudflare_api_token" {
  description = "API Token for Cloudflare to allow ExternalDNS to manage DNS records."
  type        = string
  sensitive   = true
  # No default value, this must be provided
}

variable "cloudflare_email" {
  description = "The email address associated with the Cloudflare account."
  type        = string
  sensitive   = true
  # No default value, this must be provided
}

# --- Usernames ---
variable "keycloak_admin_user" {
  description = "The admin username for Keycloak."
  type        = string
  default     = "admin"
}

variable "postgres_user" {
  description = "The username for the PostgreSQL database."
  type        = string
  default     = "postgres"
}

variable "minio_access_key" {
  description = "The access key (username) for Minio."
  type        = string
  default     = "minioadmin"
}
