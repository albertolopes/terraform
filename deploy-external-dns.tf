resource "helm_release" "external_dns" {
  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"
  namespace  = "default"
  wait       = true
  timeout    = 300

  values = [
    <<-EOT
    provider: cloudflare
    domainFilters:
      - moedabot.xyz
    policy: sync
    logLevel: debug
    rbac:
      create: true
    sources:
      - ingress
      - service

    # Usa secret existente
    env:
      - name: CF_API_TOKEN
        valueFrom:
          secretKeyRef:
            name: cloudflare-credentials
            key: CF_API_TOKEN
    EOT
  ]
}