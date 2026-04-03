# --- Variáveis do Módulo ---
variable "pg_pass" {
  description = "Password for the Authentik PostgreSQL database"
  type        = string
  sensitive   = true
}

# --- Namespace ---
resource "kubernetes_namespace_v1" "authentik" {
  metadata {
    name = "authentik"
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
      match_labels = {
        app = "authentik-postgresql"
      }
    }
    template {
      metadata {
        labels = {
          app = "authentik-postgresql"
        }
      }
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
          port {
            container_port = 5432
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
    selector = {
      app = "authentik-postgresql"
    }
    port {
      port = 5432
    }
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
      match_labels = {
        app = "authentik-redis"
      }
    }
    template {
      metadata {
        labels = {
          app = "authentik-redis"
        }
      }
      spec {
        container {
          name  = "redis"
          image = "docker.io/library/redis:alpine"
          port {
            container_port = 6379
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
    selector = {
      app = "authentik-redis"
    }
    port {
      port = 6379
    }
  }
}

# --- Authentik Server & Worker ---
resource "kubernetes_deployment_v1" "authentik_server" {
  metadata {
    name      = "authentik-server"
    namespace = kubernetes_namespace_v1.authentik.metadata[0].name
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "authentik-server"
      }
    }
    template {
      metadata {
        labels = {
          app = "authentik-server"
        }
      }
      spec {
        container {
          name    = "server"
          image   = "ghcr.io/goauthentik/server:latest"
          command = ["server"]
          env {
            name  = "AUTHENTIK_REDIS__HOST"
            value = "authentik-redis"
          }
          env {
            name  = "AUTHENTIK_POSTGRESQL__HOST"
            value = "authentik-postgresql"
          }
          env {
            name  = "AUTHENTIK_POSTGRESQL__USER"
            value = "authentik"
          }
          env {
            name  = "AUTHENTIK_POSTGRESQL__NAME"
            value = "authentik"
          }
          env {
            name  = "AUTHENTIK_POSTGRESQL__PASSWORD"
            value = var.pg_pass
          }
          port {
            container_port = 9000
          }
          port {
            container_port = 9443
          }
        }
      }
    }
  }
}

resource "kubernetes_deployment_v1" "authentik_worker" {
  metadata {
    name      = "authentik-worker"
    namespace = kubernetes_namespace_v1.authentik.metadata[0].name
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "authentik-worker"
      }
    }
    template {
      metadata {
        labels = {
          app = "authentik-worker"
        }
      }
      spec {
        container {
          name    = "worker"
          image   = "ghcr.io/goauthentik/server:latest"
          command = ["worker"]
          env {
            name  = "AUTHENTIK_REDIS__HOST"
            value = "authentik-redis"
          }
          env {
            name  = "AUTHENTIK_POSTGRESQL__HOST"
            value = "authentik-postgresql"
          }
          env {
            name  = "AUTHENTIK_POSTGRESQL__USER"
            value = "authentik"
          }
          env {
            name  = "AUTHENTIK_POSTGRESQL__NAME"
            value = "authentik"
          }
          env {
            name  = "AUTHENTIK_POSTGRESQL__PASSWORD"
            value = var.pg_pass
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "authentik_server" {
  metadata {
    name      = "authentik-server"
    namespace = kubernetes_namespace_v1.authentik.metadata[0].name
  }
  spec {
    selector = {
      app = "authentik-server"
    }
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
