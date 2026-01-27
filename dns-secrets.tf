resource "kubernetes_secret_v1" "cloudflare_api_token" {
  depends_on = [null_resource.k3d_cluster]
  metadata {
    name      = "cloudflare-api-token"
    namespace = "default" # We'll deploy external-dns in the default namespace for simplicity
  }
  data = {
    "cloudflare_api_token" = var.cloudflare_api_token
  }
}
