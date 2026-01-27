resource "helm_release" "external_dns" {
  depends_on = [kubernetes_secret_v1.cloudflare_api_token]

  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"
  namespace  = "default"

  set = [
    {
      name  = "provider"
      value = "cloudflare"
    },
    {
      name  = "cloudflare.apiToken"
      value = var.cloudflare_api_token
    },
    {
      name  = "domainFilters[0]"
      value = var.domain_name
    },
    {
      name  = "policy"
      value = "sync" # This will sync DNS records with your Ingress resources
    },
    {
      name  = "logLevel"
      value = "debug" # Useful for initial setup
    }
  ]
}
