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
    },
    {
      name  = "cloudflare.proxied"
      value = "true"
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

  # Esta é a maneira correta de injetar as credenciais no pod,
  # contornando a lógica de 'set' do chart que estava falhando.
  values = [
    <<-EOT
    extraEnvFrom:
      - secretRef:
          name: ${kubernetes_secret_v1.cloudflare_credentials.metadata[0].name}
    EOT
  ]
}
