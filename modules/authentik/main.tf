terraform {
  required_providers {
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
    null = {
      source = "hashicorp/null"
    }
  }
}

# --- Variáveis do Módulo ---
variable "pg_pass" {
  description = "Password for the shared PostgreSQL database"
  type        = string
  sensitive   = true
}

variable "redis_password" {
  description = "Password for the shared Redis instance"
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
    "AUTHENTIK_REDIS__PASSWORD"      = var.redis_password
  }
}

resource "kubernetes_config_map_v1" "authentik_env" {
  metadata {
    name      = "authentik-env"
    namespace = kubernetes_namespace_v1.authentik.metadata[0].name
  }
  data = {
    "AUTHENTIK_REDIS__HOST"              = "redis.redis.svc.cluster.local"
    "AUTHENTIK_REDIS__PORT"              = "6379"
    "AUTHENTIK_POSTGRESQL__HOST"         = "postgres.postgres.svc.cluster.local"
    "AUTHENTIK_POSTGRESQL__PORT"         = "5433"
    "AUTHENTIK_POSTGRESQL__USER"         = "postgres"
    "AUTHENTIK_POSTGRESQL__NAME"         = "authentik"
    "AUTHENTIK_ERROR_REPORTING__ENABLED" = "false"
  }
}

# --- Shared PostgreSQL bootstrap ---
resource "null_resource" "create_authentik_database" {
  provisioner "local-exec" {
    command = <<-EOT
      kubectl wait --for=condition=ready pod -l app=postgres -n postgres --timeout=180s
      if ! kubectl exec -n postgres deployment/postgres -- psql -h localhost -p 5433 -U postgres -lqt | cut -d \| -f 1 | grep -qw "authentik"; then
        kubectl exec -n postgres deployment/postgres -- psql -h localhost -p 5433 -U postgres -c 'CREATE DATABASE authentik OWNER postgres;'
      fi
      kubectl exec -n postgres deployment/postgres -- psql -h localhost -p 5433 -U postgres -d authentik -c 'GRANT ALL PRIVILEGES ON DATABASE authentik TO postgres;'
      kubectl exec -n postgres deployment/postgres -- psql -h localhost -p 5433 -U postgres -d authentik -c 'GRANT ALL ON SCHEMA public TO postgres;'
      kubectl exec -n postgres deployment/postgres -- psql -h localhost -p 5433 -U postgres -d authentik -c 'ALTER SCHEMA public OWNER TO postgres;'
    EOT

    environment = {
      KUBECONFIG = "${path.cwd}/.k3d_kubeconfig"
    }
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
    null_resource.create_authentik_database
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
          name  = "worker"
          image = "ghcr.io/goauthentik/server:latest"
          args  = ["worker"]

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
    null_resource.create_authentik_database
  ]
}
