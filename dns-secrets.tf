resource "kubernetes_secret_v1" "cloudflare_credentials" {
  depends_on = [null_resource.k3d_cluster]
  metadata {
    name      = "cloudflare-credentials"
    namespace = "default"
  }
  data = {
    # These are the environment variables that external-dns expects for API Key auth
    "CF_API_KEY"   = var.cloudflare_api_key
    "CF_API_EMAIL" = var.cloudflare_email
  }
}
