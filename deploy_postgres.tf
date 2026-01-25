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
    # Override the release name to ensure the service is just "postgres"
    {
      name  = "fullnameOverride"
      value = "postgres"
    },
    # Use the password from our central secrets file
    {
      name  = "auth.postgresPassword"
      value = kubernetes_secret_v1.postgres_credentials.data["postgresql.auth.postgresPassword"]
    },
    # Set the initial database to be created
    {
      name  = "auth.database"
      value = "keycloak"
    },
    # Configure replication: 1 primary, 1 read-only replica
    {
      name  = "primary.replicaCount"
      value = "1"
    },
    {
      name  = "readReplicas.replicaCount"
      value = "1"
    },
    # Adjust resources for a local environment
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
