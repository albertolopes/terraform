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

    # --- Injeção Direta de Variáveis de Ambiente (Tradução do seu 'kubectl patch') ---
    # Define a primeira variável de ambiente: CF_API_KEY
    {
      name  = "extraEnv[0].name"
      value = "CF_API_KEY"
    },
    {
      name  = "extraEnv[0].valueFrom.secretKeyRef.name"
      value = kubernetes_secret_v1.cloudflare_credentials.metadata[0].name
    },
    {
      name  = "extraEnv[0].valueFrom.secretKeyRef.key"
      value = "CF_API_KEY"
    },

    # Define a segunda variável de ambiente: CF_API_EMAIL
    {
      name  = "extraEnv[1].name"
      value = "CF_API_EMAIL"
    },
    {
      name  = "extraEnv[1].valueFrom.secretKeyRef.name"
      value = kubernetes_secret_v1.cloudflare_credentials.metadata[0].name
    },
    {
      name  = "extraEnv[1].valueFrom.secretKeyRef.key"
      value = "CF_API_EMAIL"
    },
    # --- Fim da Injeção ---

    # Configurações adicionais recomendadas
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
}
