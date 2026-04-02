variable "domain_name" {
  description = "Base domain name"
  type        = string
}

variable "admin_email" {
  description = "Email for Let's Encrypt certificates"
  type        = string
}

variable "enable_dashboard" {
  description = "Enable Traefik dashboard"
  type        = bool
  default     = true
}

variable "enable_access_logs" {
  description = "Enable access logs"
  type        = bool
  default     = true
}

variable "replicas" {
  description = "Number of replicas"
  type        = number
  default     = 2
}

variable "cpu_requests" {
  description = "CPU requests"
  type        = string
  default     = "100m"
}

variable "memory_requests" {
  description = "Memory requests"
  type        = string
  default     = "128Mi"
}

variable "cpu_limits" {
  description = "CPU limits"
  type        = string
  default     = "500m"
}

variable "memory_limits" {
  description = "Memory limits"
  type        = string
  default     = "512Mi"
}

variable "enable_minio" {
  description = "Enable Minio ingress"
  type        = bool
  default     = true
}

variable "dashboard_user" {
  description = "Dashboard username"
  type        = string
  default     = "admin"
}

variable "dashboard_password" {
  description = "Dashboard password"
  type        = string
  sensitive   = true
  default     = "changeme"
}