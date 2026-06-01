terraform {
  required_providers {
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }
}

locals {
  labels = {
    app = "uptime-kuma"
  }

  public_host    = "${var.hostname}.${var.domain_name}"
  ingress_active = var.enable_ingress && var.domain_name != ""
}

resource "kubernetes_namespace_v1" "uptime_kuma" {
  metadata {
    name = var.namespace
  }
}

resource "kubernetes_persistent_volume_claim_v1" "uptime_kuma_data" {
  metadata {
    name      = "uptime-kuma-data"
    namespace = kubernetes_namespace_v1.uptime_kuma.metadata[0].name
  }

  spec {
    access_modes = ["ReadWriteOnce"]

    resources {
      requests = {
        storage = var.storage_size
      }
    }

    storage_class_name = "local-path"
  }

  wait_until_bound = false
}

resource "kubernetes_deployment_v1" "uptime_kuma" {
  metadata {
    name      = "uptime-kuma"
    namespace = kubernetes_namespace_v1.uptime_kuma.metadata[0].name
    labels    = local.labels
  }

  spec {
    replicas = 1

    selector {
      match_labels = local.labels
    }

    template {
      metadata {
        labels = local.labels
      }

      spec {
        container {
          name  = "uptime-kuma"
          image = var.image

          port {
            name           = "http"
            container_port = 3001
          }

          liveness_probe {
            http_get {
              path = "/"
              port = 3001
            }

            initial_delay_seconds = 30
            period_seconds        = 20
            timeout_seconds       = 5
            failure_threshold     = 5
          }

          readiness_probe {
            http_get {
              path = "/"
              port = 3001
            }

            initial_delay_seconds = 10
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 6
          }

          volume_mount {
            name       = "data"
            mount_path = "/app/data"
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }
        }

        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.uptime_kuma_data.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "uptime_kuma" {
  metadata {
    name      = "uptime-kuma"
    namespace = kubernetes_namespace_v1.uptime_kuma.metadata[0].name
    labels    = local.labels
  }

  spec {
    selector = local.labels

    port {
      name        = "http"
      port        = 3001
      target_port = 3001
    }

    type = "ClusterIP"
  }
}

resource "kubernetes_manifest" "uptime_kuma_tls_certificate" {
  count = local.ingress_active ? 1 : 0

  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "uptime-kuma-tls"
      namespace = kubernetes_namespace_v1.uptime_kuma.metadata[0].name
    }
    spec = {
      secretName = "uptime-kuma-tls"
      issuerRef = {
        name = "letsencrypt-cloudflare"
        kind = "ClusterIssuer"
      }
      dnsNames = [
        local.public_host
      ]
    }
  }
}

resource "kubernetes_ingress_v1" "uptime_kuma" {
  count = local.ingress_active ? 1 : 0

  metadata {
    name      = "uptime-kuma"
    namespace = kubernetes_namespace_v1.uptime_kuma.metadata[0].name
    annotations = {
      "kubernetes.io/ingress.class"                      = "traefik"
      "traefik.ingress.kubernetes.io/router.entrypoints" = "web,websecure"
    }
  }

  spec {
    ingress_class_name = "traefik"

    rule {
      host = local.public_host

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service_v1.uptime_kuma.metadata[0].name

              port {
                number = 3001
              }
            }
          }
        }
      }
    }

    tls {
      hosts       = [local.public_host]
      secret_name = "uptime-kuma-tls"
    }
  }

  depends_on = [
    kubernetes_service_v1.uptime_kuma,
    kubernetes_manifest.uptime_kuma_tls_certificate
  ]
}
