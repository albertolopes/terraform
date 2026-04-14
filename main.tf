# main.tf (raiz do projeto)

# --- Infraestrutura Base ---
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

module "gitlab" {
  source        = "./modules/gitlab"
  domain_name   = "gitlab.${var.domain_name}"
  root_password = var.gitlab_root_password

  providers = {
    helm       = helm
    kubernetes = kubernetes
  }

  depends_on = [module.traefik]
}

module "postgres" {
  source = "./modules/postgres"

  providers = {
    kubernetes = kubernetes
  }

  depends_on = [module.k3d_cluster]
}