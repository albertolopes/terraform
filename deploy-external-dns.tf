resource "helm_release" "external_dns" {
  depends_on = [kubernetes_secret_v1.cloudflare_credentials]

  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"
  namespace  = "default"
  wait       = true
  timeout    = 300

  set = [
    # Configurações básicas
    {
      name  = "provider"
      value = "cloudflare"
    },
    {
      name  = "domainFilters[0]"
      value = var.domain_name
    },
    {
      name  = "policy"
      value = "sync"
    },
    {
      name  = "logLevel"
      value = "debug"
    },

    # Configuração ESPECÍFICA para Cloudflare com Secret (Sua Solução)
    {
      name  = "cloudflare.apiKey"
      value = var.cloudflare_api_key
    },
    {
      name  = "cloudflare.email"
      value = var.cloudflare_email
    },

    # Configurações adicionais recomendadas
    {
      name  = "cloudflare.proxied"
      value = "true" # Usa proxy do Cloudflare
    },
    {
      name  = "txtOwnerId"
      value = "k3d-cluster"
    },
    {
      name  = "interval"
      value = "1m"
    }
  ]
}
