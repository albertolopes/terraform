variable "domain_name" {
  description = "Base domain name"
  type        = string
}

# Ingress removido pois o Nginx está atuando como ponto de entrada principal (Proxy Reverso)
# e o K3D foi provisionado com Traefik desabilitado.
