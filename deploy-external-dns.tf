resource "helm_release" "external_dns" {
  depends_on = [kubernetes_secret_v1.cloudflare_credentials]

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
      value = var.domain_name
    },
    {
      name  = "policy"
      value = "sync"
    },
    {
      name  = "logLevel"
      value = "debug"
    }
  ]

  values = [
    <<-EOT
    extraEnvFrom:
      - secretRef:
          name: ${kubernetes_secret_v1.cloudflare_credentials.metadata[0].name}
    EOT
  ]
}
