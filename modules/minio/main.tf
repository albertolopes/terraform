terraform {
  required_providers {
    helm = {
      source = "hashicorp/helm"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }
}

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
    rootUser     = base64encode(var.minio_access_key)
    rootPassword = base64encode(var.minio_secret_key)
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

  values = [
    templatefile("${path.module}/values.yaml", {
      domain_name = var.domain_name
    })
  ]
}