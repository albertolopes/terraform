resource "kubernetes_secret_v1" "cloudflare_credentials" {
  depends_on = [null_resource.k3d_cluster]

  metadata {
    name      = "cloudflare-credentials"
    namespace = "default"
  }

  data = {
    # Usando o método de Chave de API Global + Email, que é o que o chart espera
    "CF_API_KEY"   = var.cloudflare_api_key
    "CF_API_EMAIL" = var.cloudflare_email
  }
}
