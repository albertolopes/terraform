resource "helm_release" "minio" {
  depends_on = [
    kubernetes_secret_v1.minio_credentials
  ]
  name             = "minio"
  repository       = "https://charts.min.io/"
  chart            = "minio"
  namespace        = "default"
  cleanup_on_fail  = true

  set = [
    {
      name  = "mode"
      value = "standalone"
    },
    {
      name  = "replicas"
      value = "1"
    },
    {
      name  = "accessKey"
      value = kubernetes_secret_v1.minio_credentials.data.accesskey
    },
    {
      name  = "secretKey"
      value = kubernetes_secret_v1.minio_credentials.data.secretkey
    },
    {
      name  = "resources.requests.memory"
      value = "256Mi" # Reduced memory for standalone mode
    },
    {
      name  = "ingress.enabled"
      value = "false"
    },
    {
      name  = "consoleIngress.enabled"
      value = "false"
    }
  ]
}
