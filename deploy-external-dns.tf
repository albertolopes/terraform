resource "helm_release" "external_dns" {
  depends_on = [
    kubernetes_secret_v1.cloudflare_credentials,
    null_resource.k3d_cluster
  ]

  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"
  namespace  = "default"

  # Configuração para API Key
  set {
    name  = "provider"
    value = "cloudflare"
  }

  set {
    name  = "cloudflare.apiKeySecret"
    value = "cloudflare-credentials"
  }

  set {
    name  = "cloudflare.apiKeySecretKey"
    value = "CF_API_KEY"
  }

  set {
    name  = "cloudflare.emailSecret"
    value = "cloudflare-credentials"
  }

  set {
    name  = "cloudflare.emailSecretKey"
    value = "CF_API_EMAIL"
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
}