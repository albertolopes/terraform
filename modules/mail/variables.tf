variable "domain_name" {
  description = "Dominio principal usado pelo servico de e-mail."
  type        = string
}

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID para criar registros DNS de e-mail."
  type        = string
}

variable "namespace" {
  description = "Namespace Kubernetes do servico de e-mail."
  type        = string
  default     = "mail"
}

variable "mail_hostname" {
  description = "Subdominio usado pelos protocolos SMTP/IMAP/JMAP do Stalwart."
  type        = string
  default     = "mail"
}

variable "webmail_hostname" {
  description = "Subdominio usado pelo webmail SnappyMail."
  type        = string
  default     = "webmail"
}

variable "admin_hostname" {
  description = "Subdominio usado para administracao HTTP do Stalwart."
  type        = string
  default     = "admin-mail"
}

variable "stalwart_image" {
  description = "Imagem do Stalwart."
  type        = string
  default     = "stalwartlabs/stalwart:v0.16"
}

variable "stalwart_storage_size" {
  description = "Tamanho do PVC de dados do Stalwart."
  type        = string
  default     = "50Gi"
}

variable "stalwart_recovery_admin_username" {
  description = "Usuario inicial de recuperacao do Stalwart."
  type        = string
  default     = "admin"
}

variable "stalwart_recovery_admin_password" {
  description = "Senha inicial de recuperacao do Stalwart."
  type        = string
  sensitive   = true
}

variable "snappymail_image" {
  description = "Imagem do SnappyMail."
  type        = string
  default     = "djmaze/snappymail:latest"
}

variable "snappymail_storage_size" {
  description = "Tamanho do PVC de dados/configuracao do SnappyMail."
  type        = string
  default     = "5Gi"
}

variable "enable_dns_records" {
  description = "Cria registros DNS basicos para e-mail no Cloudflare."
  type        = bool
  default     = true
}

variable "mail_server_ipv4" {
  description = "IPv4 publico apontado por mail.<dominio>. Necessario para entrega SMTP direta."
  type        = string
  default     = ""
}

variable "mail_server_ipv6" {
  description = "IPv6 publico apontado por mail.<dominio>, se utilizado."
  type        = string
  default     = ""
}
