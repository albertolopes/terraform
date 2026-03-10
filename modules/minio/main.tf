variable "minio_access_key" {
  description = "Minio access key"
  type        = string
}

variable "minio_secret_key" {
  description = "Minio secret key"
  type        = string
  sensitive   = true
}

resource "kubernetes_secret_v1" "minio_credentials" {
  metadata {
    name = "minio-credentials"
  }
  data = {
    accesskey = var.minio_access_key
    secretkey = var.minio_secret_key
  }
}

resource "helm_release" "minio" {
  depends_on = [kubernetes_secret_v1.minio_credentials]
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
      value = var.minio_access_key
    },
    {
      name  = "secretKey"
      value = var.minio_secret_key
    },
    {
      name  = "resources.requests.memory"
      value = "256Mi"
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
