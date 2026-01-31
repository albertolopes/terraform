resource "kubernetes_secret_v1" "minio_credentials" {
  depends_on = [null_resource.k3d_cluster]
  metadata {
    name = "minio-credentials"
  }
  data = {
    accesskey = var.minio_access_key
    secretkey = random_password.minio_secret_key.result
  }
}

resource "kubernetes_secret_v1" "keycloak_admin" {
  depends_on = [null_resource.k3d_cluster]
  metadata {
    name = "keycloak-admin"
  }
  data = {
    "auth.adminUser"     = var.keycloak_admin_user
    "auth.adminPassword" = random_password.keycloak_admin.result
  }
}

resource "kubernetes_secret_v1" "postgres_credentials" {
  depends_on = [null_resource.k3d_cluster]
  metadata {
    name = "postgres-credentials"
  }
  data = {
    # This matches the user created in the postgres helm chart
    "postgresql.auth.username"         = "keycloak"
    "postgresql.auth.password"         = random_password.postgres.result
    "postgresql.auth.postgresPassword" = random_password.postgres.result
  }
}

resource "kubernetes_secret_v1" "cloudflare_credentials" {
  depends_on = [null_resource.k3d_cluster]

  metadata {
    name      = "cloudflare-credentials"
    namespace = "default"
  }

  data = {
    "CF_API_KEY"   = var.cloudflare_api_key
    "CF_API_EMAIL" = var.cloudflare_email
  }
}
