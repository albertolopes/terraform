# Gerenciamento de Senhas e Segredos Aleatórios
resource "random_password" "minio_secret_key" {
  length           = 16
  special          = true
  override_special = "!#%&"
}

resource "random_password" "authentik_pg_pass" {
  length  = 32
  special = false
}

resource "random_password" "authentik_secret_key" {
  length  = 64
  special = true
}

# --- Infraestrutura Base ---
module "k3d_cluster" {
  source               = "./modules/k3d-cluster"
  cluster_config_path  = "${path.module}/cluster.yaml"
  scripts_path         = "${path.module}/scripts"
}

# --- Object Storage ---
module "minio" {
  source           = "./modules/minio"
  minio_access_key = var.minio_access_key
  minio_secret_key = random_password.minio_secret_key.result
  domain_name      = var.domain_name
  depends_on       = [module.k3d_cluster]
}

# --- Gerenciamento de Identidade (Authentik) ---
module "authentik" {
  source     = "./modules/authentik"
  pg_pass    = random_password.authentik_pg_pass.result
  secret_key = random_password.authentik_secret_key.result
  depends_on = [module.k3d_cluster]
}

# --- Servidor Web (Traefik) ---
module "traefik" {
  source           = "./modules/traefik"
  domain_name      = var.domain_name
  admin_email      = var.admin_email
  enable_dashboard = true
  depends_on       = [module.k3d_cluster]
}
