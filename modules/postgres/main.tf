variable "db_password" {
  description = "Password for the postgres database"
  type        = string
  sensitive   = true
}

resource "kubernetes_secret_v1" "postgres_credentials" {
  metadata {
    name = "postgres-credentials"
  }
  data = {
    "postgresql.auth.username"         = "keycloak"
    "postgresql.auth.password"         = var.db_password
    "postgresql.auth.postgresPassword" = var.db_password
  }
}

resource "helm_release" "postgres" {
  depends_on = [kubernetes_secret_v1.postgres_credentials]
  name             = "postgres"
  repository       = "https://charts.bitnami.com/bitnami"
  chart            = "postgresql"
  namespace        = "default"
  cleanup_on_fail  = true
  wait             = true
  timeout          = 600

  set = [
    {
      name  = "fullnameOverride"
      value = "postgres"
    },
    {
      name  = "auth.username"
      value = "keycloak"
    },
    {
      name  = "auth.password"
      value = var.db_password
    },
    {
      name  = "auth.database"
      value = "keycloak"
    },
    {
      name  = "primary.replicaCount"
      value = "1"
    },
    {
      name  = "readReplicas.replicaCount"
      value = "1"
    },
    {
      name  = "primary.resources.requests.memory"
      value = "256Mi"
    },
    {
      name  = "readReplicas.resources.requests.memory"
      value = "256Mi"
    }
  ]
}

output "db_password" {
  value     = var.db_password
  sensitive = true
}

output "db_host" {
  value = "postgres"
}
