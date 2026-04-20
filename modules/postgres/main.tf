# modules/postgres/main.tf
terraform {
  required_providers {
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }
}

resource "random_pet" "pvc_suffix" {
  length = 2
}

resource "kubernetes_namespace_v1" "postgres" {
  metadata {
    name = "postgres"
  }
}

resource "kubernetes_config_map_v1" "postgres_init" {
  metadata {
    name      = "postgres-init"
    namespace = kubernetes_namespace_v1.postgres.metadata[0].name
  }

  data = {
    "init.sql" = <<-EOT
      -- CRIA O USUÁRIO POSTGRES COM PERMISSÃO DE SUPERUSUÁRIO
      CREATE USER postgres WITH SUPERUSER PASSWORD 'postgres';

      -- Criar bancos de dados
      CREATE DATABASE gitlabhq_production OWNER postgres;
      CREATE DATABASE "na-palma" OWNER postgres;

      -- Garantir privilégios
      GRANT ALL PRIVILEGES ON DATABASE gitlabhq_production TO postgres;
      GRANT ALL PRIVILEGES ON DATABASE "na-palma" TO postgres;
    EOT
  }
}

resource "kubernetes_secret_v1" "postgres_secret" {
  metadata {
    name      = "postgres-secret"
    namespace = kubernetes_namespace_v1.postgres.metadata[0].name
  }

  data = {
    POSTGRES_USER     = base64encode("postgres")
    POSTGRES_PASSWORD = base64encode("postgres")
  }

  type = "Opaque"
}

resource "kubernetes_persistent_volume_claim_v1" "postgres" {
  metadata {
    name      = "postgres-pvc-${random_pet.pvc_suffix.id}"
    namespace = kubernetes_namespace_v1.postgres.metadata[0].name
  }

  spec {
    access_modes = ["ReadWriteOnce"]

    resources {
      requests = {
        storage = "10Gi"
      }
    }

    storage_class_name = "local-path"
  }

  wait_until_bound = false
}

resource "kubernetes_deployment_v1" "postgres" {
  metadata {
    name      = "postgres"
    namespace = kubernetes_namespace_v1.postgres.metadata[0].name
    labels = {
      app = "postgres"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "postgres"
      }
    }

    template {
      metadata {
        labels = {
          app = "postgres"
        }
      }

      spec {
        container {
          name  = "postgres"
          image = "postgres:16-alpine"

          env {
            name  = "POSTGRES_HOST_AUTH_METHOD"
            value = "md5"
          }

          env {
            name  = "PGPORT"
            value = "5433"
          }

          env {
            name = "POSTGRES_USER"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.postgres_secret.metadata[0].name
                key  = "POSTGRES_USER"
              }
            }
          }

          env {
            name = "POSTGRES_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.postgres_secret.metadata[0].name
                key  = "POSTGRES_PASSWORD"
              }
            }
          }

          env {
            name  = "POSTGRES_DB"
            value = "gitlabhq_production"
          }

          port {
            container_port = 5433
            name           = "postgres"
          }

          volume_mount {
            name       = "postgres-data"
            mount_path = "/var/lib/postgresql/data"
          }

          volume_mount {
            name       = "postgres-init"
            mount_path = "/docker-entrypoint-initdb.d"
          }

          resources {
            requests = {
              cpu    = "250m"
              memory = "512Mi"
            }
            limits = {
              cpu    = "1000m"
              memory = "1Gi"
            }
          }

          liveness_probe {
            exec {
              command = ["pg_isready", "-U", "postgres", "-p", "5433"]
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }

          readiness_probe {
            exec {
              command = ["pg_isready", "-U", "postgres", "-p", "5433"]
            }
            initial_delay_seconds = 10
            period_seconds        = 5
          }
        }

        volume {
          name = "postgres-data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.postgres.metadata[0].name
          }
        }

        volume {
          name = "postgres-init"
          config_map {
            name = kubernetes_config_map_v1.postgres_init.metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_namespace_v1.postgres,
    kubernetes_config_map_v1.postgres_init,
    kubernetes_secret_v1.postgres_secret
  ]
}

# Recurso para configurar permissões completas do PostgreSQL 16
resource "null_resource" "postgres_permissions" {
  depends_on = [kubernetes_deployment_v1.postgres]

  provisioner "local-exec" {
    command = <<-EOT
      echo "Aguardando PostgreSQL ficar pronto..."
      kubectl wait --for=condition=ready pod -l app=postgres -n postgres --timeout=120s || exit 1

      echo "Configurando permissões para o usuário postgres..."

      # Verificar e criar bancos se não existirem
      for db in gitlabhq_production "na-palma"; do
        if ! kubectl exec -n postgres deployment/postgres -- psql -h localhost -p 5433 -U postgres -lqt | cut -d \| -f 1 | grep -qw "$db"; then
          echo "Criando banco $db..."
          kubectl exec -n postgres deployment/postgres -- psql -h localhost -p 5433 -U postgres -c "CREATE DATABASE \"$db\" OWNER postgres;" || exit 1
        fi

        echo "Configurando permissões completas para $db..."
        kubectl exec -n postgres deployment/postgres -- psql -h localhost -p 5433 -U postgres -d "$db" -c "GRANT ALL PRIVILEGES ON DATABASE \"$db\" TO postgres;" || exit 1
        kubectl exec -n postgres deployment/postgres -- psql -h localhost -p 5433 -U postgres -d "$db" -c "GRANT ALL ON SCHEMA public TO postgres;" || exit 1
        kubectl exec -n postgres deployment/postgres -- psql -h localhost -p 5433 -U postgres -d "$db" -c "ALTER SCHEMA public OWNER TO postgres;" || exit 1
        kubectl exec -n postgres deployment/postgres -- psql -h localhost -p 5433 -U postgres -d "$db" -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO postgres;" || exit 1
        kubectl exec -n postgres deployment/postgres -- psql -h localhost -p 5433 -U postgres -d "$db" -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres;" || exit 1
        kubectl exec -n postgres deployment/postgres -- psql -h localhost -p 5433 -U postgres -d "$db" -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO postgres;" || exit 1
        kubectl exec -n postgres deployment/postgres -- psql -h localhost -p 5433 -U postgres -d "$db" -c "ALTER DATABASE \"$db\" OWNER TO postgres;" || exit 1
      done

      echo "Permissões completas configuradas para o usuário postgres!"
      echo "Usuário é OWNER de todos os bancos e schemas!"
    EOT

    environment = {
      KUBECONFIG = "${path.cwd}/.k3d_kubeconfig"
    }
  }
}

resource "kubernetes_service_v1" "postgres" {
  metadata {
    name      = "postgres"
    namespace = kubernetes_namespace_v1.postgres.metadata[0].name
  }

  spec {
    type = "ClusterIP"

    selector = {
      app = "postgres"
    }

    port {
      port        = 5433
      target_port = 5433
      name        = "postgres"
    }
  }

  depends_on = [null_resource.postgres_permissions]
}