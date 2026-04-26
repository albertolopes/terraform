# modules/cloudflare/variables.tf

# --- Domínio e Identificação ---
variable "domain_name" {
  description = "O domínio base gerenciado na Vercel (ex: avocadotech.site)"
  type        = string
}

variable "cloudflare_account_id" {
  description = "ID da conta Cloudflare (encontrado no dashboard lateral em 'API')"
  type        = string
  sensitive   = true
}

variable "tunnel_name" {
  description = "Nome para identificar o túnel no painel da Cloudflare"
  type        = string
  default     = "k3d-mycluster-tunnel"
}

# --- Configuração de Serviços (Dinâmica) ---
variable "services" {
  description = "Lista de serviços para mapear no Túnel e no DNS da Vercel"
  type = list(object({
    hostname = string # ex: "bot"
    service  = string # ex: "http://bitcoin-bot:3000"
  }))
  default = []
}

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID"
  type        = string
}

# --- Auxiliares ---
variable "namespace" {
  description = "Namespace padrão onde os serviços residem (útil para FQDN)"
  type        = string
  default     = "gitlab"
}