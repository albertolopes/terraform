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
module "minio" {
  source = "./modules/minio"

  domain_name      = var.domain_name
  minio_access_key = var.minio_access_key
  minio_secret_key = var.minio_secret_key

  providers = {
    helm       = helm
    kubernetes = kubernetes
  }

  depends_on = [module.k3d_cluster]
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

  depends_on = [module.postgres, module.traefik, module.minio]
}