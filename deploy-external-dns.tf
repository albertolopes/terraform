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
    },
    # CONFIGURAÇÃO PARA USAR O SECRET CRIADO
    {
      name  = "cloudflare.apiKeyFromSecret"
      value = "cloudflare-credentials"  # Nome do seu secret
    },
    {
      name  = "cloudflare.apiKeySecretKey"
      value = "CF_API_KEY"  # Chave dentro do secret
    },
    {
      name  = "cloudflare.emailFromSecret"
      value = "cloudflare-credentials"  # Mesmo secret
    },
    {
      name  = "cloudflare.emailSecretKey"
      value = "CF_API_EMAIL"  # Chave dentro do secret
    }
  ]
}