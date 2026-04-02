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
  domain_name      = var.domain_name
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
# Módulo Traefik
module "traefik" {
  source = "./modules/traefik"

  domain_name = var.domain_name
  admin_email = var.admin_email

  # Configuração opcional
  enable_dashboard = true
  enable_access_logs = true

  # Recursos
  replicas = 2
  cpu_requests = "100m"
  memory_requests = "128Mi"
  cpu_limits = "500m"
  memory_limits = "512Mi"
}

# --- Networking ---
module "networking" {
  source               = "./modules/networking"
  domain_name          = var.domain_name
  cloudflare_api_token = var.cloudflare_api_token
  depends_on           = [module.k3d_cluster]
}
output "keycloak_url" {
  value = "https://keycloak.${var.domain_name}"
}
