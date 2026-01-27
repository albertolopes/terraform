resource "kubernetes_secret_v1" "cloudflare_api_token" {
  depends_on = [null_resource.k3d_cluster]
  metadata {
    name      = "cloudflare-api-token"
    namespace = "default"
  }
  data = {
    # The external-dns chart expects the secret key to be 'api-token'
    "api-token" = var.cloudflare_api_token
  }
}
