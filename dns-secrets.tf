# resource "kubernetes_secret_v1" "cloudflare_api_token" {
#   depends_on = [null_resource.k3d_cluster]
#   metadata {
#     name      = "cloudflare-api-token"
#     namespace = "default"
#   }
#   data = {
#     # Se usando apiTokenFromSecret, a chave DEVE ser "api-token"
#     "api-token" = var.cloudflare_api_token
#     # O email é passado diretamente no chart, não no secret
#   }
# }