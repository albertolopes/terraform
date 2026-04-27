terraform {
  required_providers {
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }
}

resource "kubernetes_namespace_v1" "minio" {
  metadata {
    name = "minio"
  }
}

resource "kubernetes_secret_v1" "minio_credentials" {
  metadata {
    name      = "minio-credentials"
    namespace = kubernetes_namespace_v1.minio.metadata[0].name
  }

  data = {
    rootUser     = base64encode(var.minio_access_key)
    rootPassword = base64encode(var.minio_secret_key)
  }
}

# Deployment do MinIO com hostPath
resource "kubernetes_deployment_v1" "minio" {
  depends_on = [kubernetes_secret_v1.minio_credentials]

  metadata {
    name      = "minio"
    namespace = kubernetes_namespace_v1.minio.metadata[0].name
    labels = {
      app = "minio"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "minio"
      }
    }

    template {
      metadata {
        labels = {
          app = "minio"
        }
      }

      spec {
        container {
          name  = "minio"
          image = "minio/minio:latest"
          args  = ["server", "/data", "--console-address", ":9001"]

          port {
            container_port = 9000
            name           = "api"
          }

          port {
            container_port = 9001
            name           = "console"
          }

          env {
            name = "MINIO_ROOT_USER"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.minio_credentials.metadata[0].name
                key  = "rootUser"
              }
            }
          }

          env {
            name = "MINIO_ROOT_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.minio_credentials.metadata[0].name
                key  = "rootPassword"
              }
            }
          }

          volume_mount {
            name       = "data"
            mount_path = "/data"
          }
        }

        volume {
          name = "data"
          host_path {
            path = "/tmp/minio-data"
            type = "DirectoryOrCreate"
          }
        }
      }
    }
  }
}

# Service do MinIO
resource "kubernetes_service_v1" "minio" {
  metadata {
    name      = "minio"
    namespace = kubernetes_namespace_v1.minio.metadata[0].name
  }

  spec {
    selector = {
      app = "minio"
    }

    port {
      name        = "api"
      port        = 9000
      target_port = 9000
    }

    port {
      name        = "console"
      port        = 9001
      target_port = 9001
    }
  }
}


# Criar buckets usando um pod job
resource "kubernetes_job_v1" "create_buckets" {
  depends_on = [kubernetes_deployment_v1.minio]

  metadata {
    name      = "minio-create-buckets"
    namespace = kubernetes_namespace_v1.minio.metadata[0].name
  }

  spec {
    template {
      metadata {}
      spec {
        restart_policy = "OnFailure"

        container {
          name  = "mc"
          image = "minio/mc:latest"

          command = ["sh", "-c"]
          args = [
            <<-EOT
            echo "Waiting for MinIO to be ready..."
            sleep 10
            mc alias set myminio http://minio:9000 ${var.minio_access_key} ${var.minio_secret_key}
            mc mb myminio/terraform-state --ignore-existing
            mc mb myminio/gitlab-lfs --ignore-existing
            mc mb myminio/gitlab-artifacts --ignore-existing
            mc mb myminio/gitlab-uploads --ignore-existing
            mc mb myminio/gitlab-packages --ignore-existing
            echo "Buckets created successfully!"
            EOT
          ]
        }
      }
    }
    backoff_limit = 3
  }
}

# Ingress para o MinIO API
resource "kubernetes_ingress_v1" "minio" {
  metadata {
    name      = "minio-ingress"
    namespace = kubernetes_namespace_v1.minio.metadata[0].name
    annotations = {
      "kubernetes.io/ingress.class" = "traefik"
    }
  }

  spec {
    rule {
      host = "minio.${var.domain_name}"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.minio.metadata[0].name
              port {
                number = 9000
              }
            }
          }
        }
      }
    }
    tls {
      secret_name = "nginx-certs"
    }
  }
}

# Ingress para o MinIO Console
resource "kubernetes_ingress_v1" "minio_console" {
  metadata {
    name      = "minio-console-ingress"
    namespace = kubernetes_namespace_v1.minio.metadata[0].name
    annotations = {
      "kubernetes.io/ingress.class" = "traefik"
    }
  }

  spec {
    rule {
      host = "minio-console.${var.domain_name}"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.minio.metadata[0].name
              port {
                number = 9001
              }
            }
          }
        }
      }
    }
    tls {
      secret_name = "nginx-certs"
    }
  }
}

output "minio_url" {
  value = "https://minio.${var.domain_name}"
}

output "minio_console_url" {
  value = "http://minio.${var.domain_name}:9001"
}