resource "kubernetes_secret_v1" "cloudflare_api_token" {
  depends_on = [null_resource.k3d_cluster]
  metadata {
    name      = "cloudflare-api-token"
    namespace = "default"
  }
  data = {
    # This is the environment variable that external-dns expects for the token
    "CF_API_TOKEN" = var.cloudflare_api_token
  }
}
