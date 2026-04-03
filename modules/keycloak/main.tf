variable "admin_user" {
  description = "Keycloak admin username"
  type        = string
}

variable "admin_password" {
  description = "Keycloak admin password"
  type        = string
  sensitive   = true
}

variable "domain_name" {
  description = "Base domain name"
  type        = string
}

variable "db_password" {
  description = "Postgres database password"
  type        = string
  sensitive   = true
}

resource "kubernetes_secret_v1" "keycloak_admin" {
  metadata {
    name = "keycloak-admin"
  }
  data = {
    "auth.adminUser"     = var.admin_user
    "auth.adminPassword" = var.admin_password
  }
}

resource "kubernetes_deployment_v1" "keycloak" {
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
          # Removido argumento complexo para evitar erro de boot
          args  = ["start", "--optimized"]

          env {
            name  = "KEYCLOAK_ADMIN"
            value = var.admin_user
          }
          env {
            name  = "KEYCLOAK_ADMIN_PASSWORD"
            value = var.admin_password
          }
          env {
            name  = "KC_HOSTNAME"
            value = var.domain_name
          }
          # Variável padrão para path relativo
          env {
            name  = "KC_HTTP_RELATIVE_PATH"
            value = "/keycloak"
          }
          env {
            name  = "KC_HOSTNAME_STRICT"
            value = "false"
          }
          env {
            name  = "KC_PROXY"
            value = "edge"
          }
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
            value = var.db_password
          }
          env {
            name  = "KC_HEALTH_ENABLED"
            value = "true"
          }

          port {
            name           = "http"
            container_port = 8080
          }

          # Readiness probe voltando para a porta 8080 no path configurado
          readiness_probe {
            http_get {
              path = "/keycloak/health/live"
              port = 8080
            }
            initial_delay_seconds = 40
            period_seconds        = 10
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
