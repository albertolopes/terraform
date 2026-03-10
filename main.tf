# Gerenciamento de Senhas e Segredos Aleatórios
resource "random_password" "keycloak_admin" {
  length           = 16
  special          = true
  override_special = "!#%&"
}

resource "random_password" "postgres" {
  length           = 16
  special          = true
  override_special = "!#%&"
}

resource "random_password" "minio_secret_key" {
  length           = 16
  special          = true
  override_special = "!#%&"
}

# --- Infraestrutura Base ---
module "k3d_cluster" {
  source               = "./modules/k3d-cluster"
  cluster_config_path  = "${path.module}/cluster.yaml"
  scripts_path         = "${path.module}/scripts"
}

# --- Banco de Dados ---
module "postgres" {
  source      = "./modules/postgres"
  db_password = random_password.postgres.result
  depends_on  = [module.k3d_cluster]
}

# --- Object Storage ---
module "minio" {
  source           = "./modules/minio"
  minio_access_key = var.minio_access_key
  minio_secret_key = random_password.minio_secret_key.result
  depends_on       = [module.k3d_cluster]
}

# --- Gerenciamento de Identidade ---
module "keycloak" {
  source         = "./modules/keycloak"
  admin_user     = var.keycloak_admin_user
  admin_password = random_password.keycloak_admin.result
  domain_name    = var.domain_name
  db_password    = random_password.postgres.result
  depends_on     = [module.postgres]
}

# --- Servidor Web ---
module "nginx" {
  source      = "./modules/nginx"
  domain_name = var.domain_name
  depends_on  = [module.k3d_cluster]
}

# --- Networking ---
module "networking" {
  source               = "./modules/networking"
  domain_name          = var.domain_name
  cloudflare_api_token = var.cloudflare_api_token
  depends_on           = [module.k3d_cluster, module.keycloak, module.nginx]
}
