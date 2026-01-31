resource "helm_release" "external_dns" {
  depends_on = [kubernetes_secret_v1.cloudflare_credentials]

  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"
  namespace  = "default"
  wait       = true
  timeout    = 300

  # Configurações básicas
  set {
    name  = "provider"
    value = "cloudflare"
  }

  set {
    name  = "domainFilters[0]"
    value = var.domain_name
  }

  set {
    name  = "policy"
    value = "sync"
  }

  set {
    name  = "logLevel"
    value = "debug"
  }

  # Configuração ESPECÍFICA para Cloudflare com Secret
  set {
    name  = "cloudflare.apiKeySecret"
    value = kubernetes_secret_v1.cloudflare_credentials.metadata[0].name
  }

  set {
    name  = "cloudflare.apiKeySecretKey"
    value = "CF_API_KEY"
  }

  set {
    name  = "cloudflare.emailSecret"
    value = kubernetes_secret_v1.cloudflare_credentials.metadata[0].name
  }

  set {
    name  = "cloudflare.emailSecretKey"
    value = "CF_API_EMAIL"
  }

  # Configurações adicionais recomendadas
  set {
    name  = "cloudflare.proxied"
    value = "true"  # Usa proxy do Cloudflare
  }

  set {
    name  = "txtOwnerId"
    value = "k3d-cluster"
  }

  set {
    name  = "interval"
    value = "1m"
  }
}