resource "kubernetes_secret_v1" "minio_credentials" {
  depends_on = [null_resource.k3d_cluster]
  metadata {
    name = "minio-credentials"
  }
  data = {
    accesskey = "minio"
    secretkey = "minio123"
  }
}

resource "kubernetes_secret_v1" "keycloak_admin" {
  depends_on = [null_resource.k3d_cluster]
  metadata {
    name = "keycloak-admin"
  }
  data = {
    "auth.adminUser"     = "admin"
    "auth.adminPassword" = "admin"
  }
}

resource "kubernetes_secret_v1" "postgres_credentials" {
  depends_on = [null_resource.k3d_cluster]
  metadata {
    name = "postgres-credentials"
  }
  data = {
    "postgresql.auth.postgresPassword" = "postgres"
  }
}
