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

resource "kubernetes_namespace_v1" "redis" {
  metadata {
    name = var.namespace
  }
}

# Secret para a senha do Redis
resource "kubernetes_secret_v1" "redis_password" {
  metadata {
    name      = "redis-password-secret"
    namespace = kubernetes_namespace_v1.redis.metadata[0].name
  }

  type = "Opaque"

  data = {
    "redis-password" = var.redis_password
  }
}

# PVC para armazenamento persistente
resource "kubernetes_persistent_volume_claim_v1" "redis" {
  metadata {
    name      = "redis-pvc"
    namespace = kubernetes_namespace_v1.redis.metadata[0].name
  }

  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = var.storage_size
      }
    }
  }

  wait_until_bound = false # Resolve o deadlock do WaitForFirstConsumer
}


# Deployment do Redis
resource "kubernetes_deployment_v1" "redis" {
  metadata {
    name      = "redis"
    namespace = kubernetes_namespace_v1.redis.metadata[0].name
    labels = {
      app = "redis"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "redis"
      }
    }

    template {
      metadata {
        labels = {
          app = "redis"
        }
      }

      spec {
        container {
          name  = "redis"
          image = "redis:7.2-alpine" # Voltei para a imagem oficial e leve

          port {
            container_port = 6379
            name           = "redis"
          }

          env {
            name = "REDIS_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.redis_password.metadata[0].name
                key  = "redis-password"
              }
            }
          }

          args = [
            "--requirepass",
            "$(REDIS_PASSWORD)",
            "--appendonly",
            "yes"
          ]

          resources {
            requests = {
              cpu    = var.resources.requests.cpu
              memory = var.resources.requests.memory
            }
            limits = {
              cpu    = var.resources.limits.cpu
              memory = var.resources.limits.memory
            }
          }

          volume_mount {
            name       = "redis-data"
            mount_path = "/data"
          }

          liveness_probe {
            exec {
              command = ["sh", "-c", "redis-cli -a $(REDIS_PASSWORD) ping"]
            }
            initial_delay_seconds = 30
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 3
          }

          readiness_probe {
            exec {
              command = ["sh", "-c", "redis-cli -a $(REDIS_PASSWORD) ping"]
            }
            initial_delay_seconds = 5
            period_seconds        = 5
            timeout_seconds       = 3
            failure_threshold     = 3
          }
        }

        volume {
          name = "redis-data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.redis.metadata[0].name
          }
        }
      }
    }
  }
}

# Service do Redis
resource "kubernetes_service_v1" "redis" {
  metadata {
    name      = "redis"
    namespace = kubernetes_namespace_v1.redis.metadata[0].name
    labels = {
      app = "redis"
    }
  }

  spec {
    selector = {
      app = "redis"
    }

    port {
      name        = "redis"
      port        = 6379
      target_port = 6379
    }

    type = "ClusterIP"
  }
}

# Outputs
output "redis_host" {
  value = "redis.${var.namespace}.svc.cluster.local"
}

output "redis_port" {
  value = 6379
}

output "redis_password" {
  value     = var.redis_password
  sensitive = true
}

output "redis_namespace" {
  value = var.namespace
}
