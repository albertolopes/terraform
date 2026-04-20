variable "namespace" {
  description = "Kubernetes namespace for Redis"
  type        = string
  default     = "redis"
}

variable "redis_password" {
  description = "Redis password"
  type        = string
  sensitive   = true
  default     = "redis-secure-password"
}

variable "storage_size" {
  description = "Size of the persistent volume"
  type        = string
  default     = "10Gi"
}

variable "resources" {
  description = "Resource requests and limits"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "100m"
      memory = "256Mi"
    }
    limits = {
      cpu    = "500m"
      memory = "512Mi"
    }
  }
}