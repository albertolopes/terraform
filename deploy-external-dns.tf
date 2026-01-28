resource "helm_release" "external_dns" {
  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"
  namespace  = "default"
  wait       = true
  timeout    = 300

  set = [
    {
      name  = "provider"
      value = "cloudflare"
    },
    {
      name  = "domainFilters[0]"
      value = var.domain_name  # "moedabot.xyz"
    },
    {
      name  = "policy"
      value = "sync"
    },
    {
      name  = "logLevel"
      value = "debug"
    },
    # CONFIGURAÇÃO PARA GLOBAL API KEY
    {
      name  = "cloudflare.apiKey"
      value = var.cloudflare_api_token  # Sua Global API Key
    },
    {
      name  = "cloudflare.email"
      value = var.cloudflare_email      # Seu email da conta
    },
    # Configurações adicionais recomendadas
    {
      name  = "rbac.create"
      value = "true"
    },
    {
      name  = "sources[0]"
      value = "ingress"
    },
    {
      name  = "sources[1]"
      value = "service"
    }
  ]
}