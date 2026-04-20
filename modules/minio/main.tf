terraform {
  required_providers {
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
    helm = {
      source = "hashicorp/helm"
    }
  }
}

resource "kubernetes_secret_v1" "minio_credentials" {
  metadata {
    name      = "minio-credentials"
    namespace = "default"
  }

  data = {
    rootUser     = base64encode(var.minio_access_key)
    rootPassword = base64encode(var.minio_secret_key)
  }
}

resource "helm_release" "minio" {
  depends_on      = [kubernetes_secret_v1.minio_credentials]
  name            = "minio"
  repository      = "https://charts.bitnami.com/bitnami"
  chart           = "minio"
  version         = "14.7.6" 
  namespace       = "default"
  cleanup_on_fail = true
  wait            = true
  timeout         = 600

  values = [
    templatefile("${path.module}/values.yaml", {
      domain_name = var.domain_name
    })
  ]
}

output "minio_url" {
  value = "https://minio.${var.domain_name}"
}