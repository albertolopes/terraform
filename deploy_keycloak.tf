resource "kubernetes_deployment_v1" "keycloak" {
  depends_on = [helm_release.postgres]
  metadata {
    name = "keycloak"
  }
  spec {
    replicas = 1
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
          image = "quay.io/keycloak/keycloak:latest"
          args  = ["start"]

          env {
            name  = "KEYCLOAK_ADMIN"
            value = var.keycloak_admin_user
          }
          env {
            name  = "KEYCLOAK_ADMIN_PASSWORD"
            value = random_password.keycloak_admin.result
          }

          # --- Configuração de Hostname v2 (Moderna e Correta) ---
          env {
            name  = "KC_HOSTNAME_URL"
            value = "https://keycloak.${var.domain_name}"
          }
          env {
            name  = "KC_PROXY"
            value = "edge"
          }
          # --- Fim da Configuração de Hostname ---

          env {
            name  = "KC_DB"
            value = "postgres"
          }
          env {
            name  = "KC_DB_URL"
            value = "jdbc:postgresql://postgres:5432/keycloak"
          }
          env {
            name  = "KC_DB_USERNAME"
            value = "keycloak"
          }
          env {
            name  = "KC_DB_PASSWORD"
            value = random_password.postgres.result
          }

          port {
            name           = "http"
            container_port = 8080
          }
          port {
            name           = "management"
            container_port = 9000
          }

          readiness_probe {
            http_get {
              path = "/realms/master"
              port = 8080
            }
            initial_delay_seconds = 30
            period_seconds        = 10
            failure_threshold     = 3
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
