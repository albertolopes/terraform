variable "minio_access_key" {
  description = "Minio root user"
  type        = string
}

variable "minio_secret_key" {
  description = "Minio root password"
  type        = string
  sensitive   = true
}

variable "domain_name" {
  description = "Base domain name"
  type        = string
}

resource "kubernetes_secret_v1" "minio_credentials" {
  metadata {
    name      = "minio-credentials"
    namespace = "default"
  }
  data = {
    rootUser     = var.minio_access_key
    rootPassword = var.minio_secret_key
  }
}

resource "helm_release" "minio" {
  depends_on      = [kubernetes_secret_v1.minio_credentials]
  name            = "minio"
  repository      = "https://charts.bitnami.com/bitnami"
  chart           = "minio"
  namespace       = "default"
  cleanup_on_fail = true
  wait            = true
  timeout         = 600

  set {
    name  = "auth.existingSecret"
    value = "minio-credentials"
  }
  set {
    name  = "service.type"
    value = "ClusterIP"
  }
  set {
    name  = "defaultBuckets"
    value = "terraform-state"
  }
  set {
    name  = "extraEnvVars[0].name"
    value = "MINIO_BROWSER_REDIRECT_URL"
  }
  set {
    name  = "extraEnvVars[0].value"
    value = "https://${var.domain_name}/console"
  }
}
