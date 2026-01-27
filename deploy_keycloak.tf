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
            name  = "KEYCLOAK_ADMIN"
            value = var.keycloak_admin_user
          }
          env {
            name  = "KEYCLOAK_ADMIN_PASSWORD"
            value = random_password.keycloak_admin.result
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
            value = var.postgres_user
          }
          env {
            name  = "KC_DB_PASSWORD"
            value = random_password.postgres.result
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
