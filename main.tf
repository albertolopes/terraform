#main.tf

# --- Cloudflare Tunnel & Vercel DNS ---
# Este módulo cria o túnel e já configura o DNS na Vercel
module "cloudflare" {
  source                = "./modules/cloudflare"
  domain_name           = var.domain_name
  cloudflare_account_id = var.cloudflare_account_id
  cloudflare_zone_id    = var.cloudflare_zone_id

  # Apontamos todos os subdomínios para o Traefik
  # O uso do "*" (wildcard) permite que novos serviços criados via GitLab pipelines 
  # funcionem automaticamente sem precisar mexer no Terraform.
  services = [
    { hostname = "*", service = "http://traefik.traefik.svc.cluster.local:80" },
    { hostname = "traefik", service = "http://traefik.traefik.svc.cluster.local:80" },
    { hostname = "gitlab", service = "http://traefik.traefik.svc.cluster.local:80" },
    { hostname = "registry", service = "http://traefik.traefik.svc.cluster.local:80" },
    { hostname = "minio", service = "http://traefik.traefik.svc.cluster.local:80" },
    { hostname = "minio-console", service = "http://traefik.traefik.svc.cluster.local:80" },
    { hostname = "authentik", service = "http://traefik.traefik.svc.cluster.local:80" }
  ]

  providers = {
    cloudflare = cloudflare
    kubernetes = kubernetes
  }

  depends_on = [module.k3d_cluster]
}

module "k3d_cluster" {
  source              = "./modules/k3d-cluster"
  cluster_config_path = "${path.module}/cluster.yaml"
  scripts_path        = "${path.module}/scripts"
}

module "postgres" {
  source = "./modules/postgres"
  providers = {
    kubernetes = kubernetes
  }
  depends_on = [module.k3d_cluster]
}

module "networking" {
  source               = "./modules/networking"
  domain_name          = var.domain_name
  cloudflare_api_token = var.cloudflare_api_token

  providers = {
    helm       = helm
    kubernetes = kubernetes
    kubectl    = kubectl
  }

  depends_on = [module.k3d_cluster]
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

  depends_on = [module.k3d_cluster, module.networking]
}

# --- Redis ---
module "redis" {
  source         = "./modules/redis"
  redis_password = var.redis_password

  providers = {
    kubernetes = kubernetes
  }

  depends_on = [module.k3d_cluster]
}

# --- MinIO ---
module "minio" {
  source           = "./modules/minio"
  domain_name      = var.domain_name
  minio_access_key = var.minio_access_key
  minio_secret_key = var.minio_secret_key

  providers = {
    kubernetes = kubernetes
  }

  depends_on = [module.k3d_cluster]
}

# --- GitLab ---
module "gitlab" {
  source = "./modules/gitlab"

  # Se o seu domínio é "exemplo.com", aqui vira "gitlab.exemplo.com"
  domain_name        = "gitlab.${var.domain_name}"
  namespace          = "gitlab"
  root_password      = var.gitlab_root_password
  minio_access_key   = var.minio_access_key
  minio_secret_key   = var.minio_secret_key

  redis_password     = var.redis_password

  runner_authentication_token = var.gitlab_runner_token

  providers = {
    helm       = helm
    kubernetes = kubernetes
  }

  depends_on = [module.traefik, module.minio, module.postgres, module.cloudflare]
}
