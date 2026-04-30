# --- Cluster & Infra Base ---

module "k3d_cluster" {
  source              = "./modules/k3d-cluster"
  cluster_config_path = "${path.module}/cluster.yaml"
  scripts_path        = "${path.module}/scripts"
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

# --- Cloudflare Tunnel ---

module "cloudflare" {
  source                = "./modules/cloudflare"
  domain_name           = var.domain_name
  cloudflare_account_id = var.cloudflare_account_id
  cloudflare_zone_id    = var.cloudflare_zone_id

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

# --- Databases & Storage (A Fundação) ---

module "postgres" {
  source = "./modules/postgres"
  providers = {
    kubernetes = kubernetes
  }
  depends_on = [module.k3d_cluster]
}

module "redis" {
  source         = "./modules/redis"
  redis_password = var.redis_password
  providers = { kubernetes = kubernetes }
  depends_on = [module.k3d_cluster]
}

module "minio" {
  source           = "./modules/minio"
  domain_name      = var.domain_name
  minio_access_key = var.minio_access_key
  minio_secret_key = var.minio_secret_key
  providers = { kubernetes = kubernetes }
  depends_on = [module.k3d_cluster]
}

# --- Ingress Controller (Traefik) ---

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

# --- ESTRUTURA PARA O GITLAB (O Ajuste Mestre) ---

# 1. Criamos o Namespace explicitamente no root
resource "kubernetes_namespace_v1" "gitlab" {
  metadata {
    name = "gitlab"
  }
  depends_on = [module.k3d_cluster]
}

# 2. Criamos o Middleware de HTTPS ANTES do GitLab
resource "kubernetes_manifest" "traefik_middleware" {
  manifest = {
    "apiVersion" = "traefik.io/v1alpha1"
    "kind"       = "Middleware"
    "metadata" = {
      "name"      = "traefik-force-https-header"
      "namespace" = kubernetes_namespace_v1.gitlab.metadata[0].name
    }
    "spec" = {
      "headers" = {
        "customRequestHeaders" = {
          "X-Forwarded-Proto" = "https"
          "X-Forwarded-Ssl"   = "on"
        }
      }
    }
  }
  depends_on = [kubernetes_namespace_v1.gitlab]
}

# 3. Módulo GitLab (Agora dependente da rede pronta)
module "gitlab" {
  source = "./modules/gitlab"

  domain_name        = "gitlab.${var.domain_name}"
  namespace          = kubernetes_namespace_v1.gitlab.metadata[0].name # Passa o nome do NS criado acima
  root_password      = var.gitlab_root_password
  minio_access_key   = var.minio_access_key
  minio_secret_key   = var.minio_secret_key
  redis_password     = var.redis_password
  runner_authentication_token = var.gitlab_runner_token

  trusted_proxies    = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "127.0.0.1"]

  providers = {
    helm       = helm
    kubernetes = kubernetes
  }

  depends_on = [
    module.traefik,
    module.minio,
    module.postgres,
    module.cloudflare,
    kubernetes_manifest.traefik_middleware
  ]
}