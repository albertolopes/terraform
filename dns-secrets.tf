resource "kubernetes_secret_v1" "cloudflare_api_token" {
  depends_on = [null_resource.k3d_cluster]
  metadata {
    name      = "cloudflare-api-token"
    namespace = "default"
  }
  data = {
    # These are the environment variables that external-dns expects
    "CF_API_TOKEN" = var.cloudflare_api_token
    "CF_API_EMAIL" = var.cloudflare_email
  }
}
