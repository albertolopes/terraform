# --- Variáveis do Módulo ---
variable "pg_pass" {
  description = "Password for the Authentik PostgreSQL database"
  type        = string
  sensitive   = true
}

variable "secret_key" {
  description = "Authentik secret key"
  type        = string
  sensitive   = true
}

# --- Namespace ---
resource "kubernetes_namespace_v1" "authentik" {
  metadata {
    name = "authentik"
  }
}

# --- ConfigMap & Secret Base ---
resource "kubernetes_secret_v1" "authentik_env" {
  metadata {
    name      = "authentik-env"
    namespace = kubernetes_namespace_v1.authentik.metadata[0].name
  }
  data = {
    "AUTHENTIK_SECRET_KEY"           = var.secret_key
    "AUTHENTIK_POSTGRESQL__PASSWORD" = var.pg_pass
  }
}

resource "kubernetes_config_map_v1" "authentik_env" {
  metadata {
    name      = "authentik-env"
    namespace = kubernetes_namespace_v1.authentik.metadata[0].name
  }
  data = {
    "AUTHENTIK_REDIS__HOST"        = "authentik-redis"
    "AUTHENTIK_POSTGRESQL__HOST"   = "authentik-postgresql"
    "AUTHENTIK_POSTGRESQL__USER"   = "authentik"
    "AUTHENTIK_POSTGRESQL__NAME"   = "authentik"
    "AUTHENTIK_ERROR_REPORTING__ENABLED" = "false"
  }
}

# --- PostgreSQL ---
resource "kubernetes_deployment_v1" "postgresql" {
  metadata {
    name      = "authentik-postgresql"
    namespace = kubernetes_namespace_v1.authentik.metadata[0].name
  }
  spec {
    replicas = 1
    selector {
      match_labels = { app = "authentik-postgresql" }
    }
    template {
      metadata { labels = { app = "authentik-postgresql" } }
      spec {
        container {
          name  = "postgres"
          image = "docker.io/library/postgres:16-alpine"
          env {
            name  = "POSTGRES_PASSWORD"
            value = var.pg_pass
          }
          env {
            name  = "POSTGRES_USER"
            value = "authentik"
          }
          env {
            name  = "POSTGRES_DB"
            value = "authentik"
          }
          port { container_port = 5432 }

          liveness_probe {
            exec {
              command = ["pg_isready", "-d", "authentik", "-U", "authentik"]
            }
            initial_delay_seconds = 20
            period_seconds        = 30
            failure_threshold     = 5
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "postgresql" {
  metadata {
    name      = "authentik-postgresql"
    namespace = kubernetes_namespace_v1.authentik.metadata[0].name
  }
  spec {
    selector = { app = "authentik-postgresql" }
    port { port = 5432 }
  }
}

# --- Redis ---
resource "kubernetes_deployment_v1" "redis" {
  metadata {
    name      = "authentik-redis"
    namespace = kubernetes_namespace_v1.authentik.metadata[0].name
  }
  spec {
    replicas = 1
    selector {
      match_labels = { app = "authentik-redis" }
    }
    template {
      metadata { labels = { app = "authentik-redis" } }
      spec {
        container {
          name    = "redis"
          image   = "docker.io/library/redis:alpine"
          command = ["redis-server", "--save", "60", "1", "--loglevel", "warning"]
          port { container_port = 6379 }

          liveness_probe {
            exec {
              command = ["sh", "-c", "redis-cli ping | grep PONG"]
            }
            initial_delay_seconds = 20
            period_seconds        = 30
            failure_threshold     = 5
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "redis" {
  metadata {
    name      = "authentik-redis"
    namespace = kubernetes_namespace_v1.authentik.metadata[0].name
  }
  spec {
    selector = { app = "authentik-redis" }
    port { port = 6379 }
  }
}

# --- Authentik Server ---
resource "kubernetes_deployment_v1" "authentik_server" {
  metadata {
    name      = "authentik-server"
    namespace = kubernetes_namespace_v1.authentik.metadata[0].name
  }
  spec {
    replicas = 1
    selector {
      match_labels = { app = "authentik-server" }
    }
    template {
      metadata { labels = { app = "authentik-server" } }
      spec {
        container {
          name    = "server"
          image   = "ghcr.io/goauthentik/server:latest"
          command = ["server"]

          env_from {
            config_map_ref { name = kubernetes_config_map_v1.authentik_env.metadata[0].name }
          }
          env_from {
            secret_ref { name = kubernetes_secret_v1.authentik_env.metadata[0].name }
          }

          port { container_port = 9000 }
          port { container_port = 9443 }
        }
      }
    }
  }
  depends_on = [
    kubernetes_deployment_v1.postgresql,
    kubernetes_deployment_v1.redis
  ]
}

resource "kubernetes_service_v1" "authentik_server" {
  metadata {
    name      = "authentik-server"
    namespace = kubernetes_namespace_v1.authentik.metadata[0].name
  }
  spec {
    selector = { app = "authentik-server" }
    port {
      name = "http"
      port = 9000
    }
    port {
      name = "https"
      port = 9443
    }
  }
}

# --- Authentik Worker ---
resource "kubernetes_deployment_v1" "authentik_worker" {
  metadata {
    name      = "authentik-worker"
    namespace = kubernetes_namespace_v1.authentik.metadata[0].name
  }
  spec {
    replicas = 1
    selector {
      match_labels = { app = "authentik-worker" }
    }
    template {
      metadata { labels = { app = "authentik-worker" } }
      spec {
        container {
          name    = "worker"
          image   = "ghcr.io/goauthentik/server:latest"
          command = ["worker"]

          env_from {
            config_map_ref { name = kubernetes_config_map_v1.authentik_env.metadata[0].name }
          }
          env_from {
            secret_ref { name = kubernetes_secret_v1.authentik_env.metadata[0].name }
          }
        }
      }
    }
  }
  depends_on = [
    kubernetes_deployment_v1.postgresql,
    kubernetes_deployment_v1.redis
  ]
}
