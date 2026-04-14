# modules/traefik/variables.tf

variable "replicas" {
  description = "Número de réplicas do Traefik"
  type        = number
  default     = 1
}

variable "cpu_requests" {
  description = "CPU requests para o Traefik"
  type        = string
  default     = "100m"
}

variable "cpu_limits" {
  description = "CPU limits para o Traefik"
  type        = string
  default     = "500m"
}

variable "memory_requests" {
  description = "Memória requests para o Traefik"
  type        = string
  default     = "128Mi"
}

variable "memory_limits" {
  description = "Memória limits para o Traefik"
  type        = string
  default     = "512Mi"
}

variable "enable_dashboard" {
  description = "Habilitar dashboard do Traefik"
  type        = bool
  default     = true
}

variable "domain_name" {
  description = "Domínio para acessar o dashboard"
  type        = string
  default     = "avocado.tail799250.ts.net"
}