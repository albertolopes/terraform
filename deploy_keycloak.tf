resource "kubernetes_deployment_v1" "keycloak" {
  depends_on = [helm_release.postgres]
  metadata {
    name = "keycloak"
  }
  spec {
    replicas = 1 # Reduced to 1 replica for stability
    selector {
      match_labels = {
        app = "keycloak"
      }
    }
    template {
      metadata {
        labels = {
          app = "keycloak"
        }
      }
      spec {
        container {
          name  = "keycloak"
          image = "quay.io/keycloak/keycloak:25.0.0"
          args  = ["start"] # Changed to 'start' for production mode

          env {
            name = "KEYCLOAK_ADMIN"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.keycloak_admin.metadata[0].name
                key  = "auth.adminUser"
              }
            }
          }
          env {
            name = "KEYCLOAK_ADMIN_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.keycloak_admin.metadata[0].name
                key  = "auth.adminPassword"
              }
            }
          }
          env {
            name  = "KC_HOSTNAME"
            value = "keycloak.${var.domain_name}"
          }
          env {
            name  = "KC_DB"
            value = "postgres"
          }
          env {
            name  = "KC_DB_URL_HOST"
            value = "postgres"
          }
          env {
            name  = "KC_DB_USERNAME"
            value = "postgres"
          }
          env {
            name = "KC_DB_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.postgres_credentials.metadata[0].name
                key  = "postgresql.auth.postgresPassword"
              }
            }
          }
          env {
            name  = "KC_DB_DATABASE"
            value = "keycloak" # Connect to the correct database
          }
          env {
            name  = "KC_PROXY"
            value = "edge"
          }

          port {
            name           = "http"
            container_port = 8080
          }
          port {
            name           = "management"
            container_port = 9000
          }

          resources {
            requests = {
              cpu    = "500m"
              memory = "512Mi"
            }
            limits = {
              cpu    = "1"
              memory = "1Gi"
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "keycloak" {
  depends_on = [kubernetes_deployment_v1.keycloak]
  metadata {
    name = "keycloak"
  }
  spec {
    selector = {
      app = "keycloak"
    }
    port {
      name        = "http"
      port        = 8080
      target_port = 8080
    }
  }
}
