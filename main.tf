module "k3d_cluster" {
  source              = "./modules/k3d-cluster"
  cluster_config_path = "${path.module}/cluster.yaml"
  scripts_path        = "${path.module}/scripts"
}

# --- Servidor Web (Traefik) ---
module "traefik" {
  source           = "./modules/traefik"
  domain_name      = var.domain_name
  enable_dashboard = true

  providers = {
    helm       = helm
    kubernetes = kubernetes
  }

  depends_on = [module.k3d_cluster]
}

# --- Banco de Dados PostgreSQL ---
module "postgres" {
  source = "./modules/postgres"

  providers = {
    kubernetes = kubernetes
  }

  depends_on = [module.k3d_cluster]
}

# --- MinIO Object Storage ---
resource "kubernetes_secret_v1" "minio_credentials" {
  depends_on = [module.k3d_cluster]

  metadata {
    name      = "minio-credentials"
    namespace = "default"
  }

  data = {
    rootUser     = base64encode(var.minio_access_key)
    rootPassword = base64encode(var.minio_secret_key)
  }
}

resource "helm_release" "minio" {
  depends_on      = [kubernetes_secret_v1.minio_credentials, module.k3d_cluster]
  name            = "minio"
  repository      = "https://charts.bitnami.com/bitnami"
  chart           = "minio"
  namespace       = "default"
  cleanup_on_fail = true
  wait            = true
  timeout         = 600

  values = [
    templatefile("${path.module}/values.yaml", {
      domain_name = var.domain_name
    })
  ]
}

# --- GitLab ---
module "gitlab" {
  source = "./modules/gitlab"

  domain_name        = "gitlab.${var.domain_name}"
  root_password      = var.gitlab_root_password
  minio_access_key   = var.minio_access_key
  minio_secret_key   = var.minio_secret_key

  providers = {
    helm       = helm
    kubernetes = kubernetes
  }

  depends_on = [module.postgres, module.traefik, helm_release.minio]
}