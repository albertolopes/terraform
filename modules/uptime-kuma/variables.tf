variable "namespace" {
  description = "Namespace Kubernetes para o Uptime Kuma."
  type        = string
  default     = "uptime-kuma"
}

variable "domain_name" {
  description = "Dominio base usado no ingress do Uptime Kuma."
  type        = string
}

variable "hostname" {
  description = "Subdominio publico do Uptime Kuma."
  type        = string
  default     = "uptime"
}

variable "image" {
  description = "Imagem do Uptime Kuma."
  type        = string
  default     = "louislam/uptime-kuma:1"
}

variable "storage_size" {
  description = "Tamanho do volume persistente do Uptime Kuma."
  type        = string
  default     = "5Gi"
}

variable "enable_ingress" {
  description = "Habilita Ingress publico para o Uptime Kuma."
  type        = bool
  default     = true
}

variable "enable_certificate" {
  description = "Habilita Certificate/TLS via cert-manager para o Ingress do Uptime Kuma."
  type        = bool
  default     = false
}
