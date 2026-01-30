resource "helm_release" "external_dns" {
  depends_on = [kubernetes_secret_v1.cloudflare_api_token]

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
    extraEnv:
      - name: CF_API_TOKEN
        valueFrom:
          secretKeyRef:
            name: ${kubernetes_secret_v1.cloudflare_api_token.metadata[0].name}
            key: CF_API_TOKEN
      - name: CF_API_EMAIL
        valueFrom:
          secretKeyRef:
            name: ${kubernetes_secret_v1.cloudflare_api_token.metadata[0].name}
            key: CF_API_EMAIL
    EOT
  ]
}
