resource "helm_release" "postgres" {
  depends_on = [
    kubernetes_secret_v1.postgres_credentials
  ]
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
      value = var.postgres_user
    },
    {
      name  = "auth.postgresPassword"
      value = random_password.postgres.result
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
