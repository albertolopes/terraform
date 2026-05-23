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

# --- Databases & Storage ---

module "postgres" {
  source = "./modules/postgres"
  providers = {
    kubernetes = kubernetes
    random     = random
  }
  depends_on = [module.k3d_cluster]
}

module "redis" {
  source         = "./modules/redis"
  redis_password = var.redis_password
  providers      = { kubernetes = kubernetes }
  depends_on     = [module.k3d_cluster]
}

module "minio" {
  source           = "./modules/minio"
  domain_name      = var.domain_name
  minio_access_key = var.minio_access_key
  minio_secret_key = var.minio_secret_key
  providers        = { kubernetes = kubernetes }
  depends_on       = [module.k3d_cluster, module.networking]
}

# --- Ingress Controller (Traefik) ---

module "traefik" {
  source           = "./modules/traefik"
  domain_name      = var.domain_name
  enable_dashboard = true
  providers = {
    helm       = helm
    kubernetes = kubernetes
    kubectl    = kubectl
  }
  depends_on = [module.k3d_cluster, module.networking]
}

resource "random_password" "authentik_secret_key" {
  length  = 64
  special = false
}

module "authentik" {
  source         = "./modules/authentik"
  domain_name    = var.domain_name
  pg_pass        = var.postgres_password
  redis_password = var.redis_password
  secret_key     = random_password.authentik_secret_key.result

  providers = {
    kubernetes = kubernetes
  }

  depends_on = [
    module.postgres,
    module.redis,
    module.traefik
  ]
}

module "tesseract" {
  source              = "./modules/tesseract"
  domain_name         = var.domain_name
  hostname            = var.tesseract_hostname
  api_image           = var.tesseract_api_image
  tesseract_ocr_image = var.tesseract_ocr_image
  api_build_context   = null
  api_dockerfile      = null
  ocr_build_context   = path.module
  ocr_dockerfile      = "${path.module}/docker/tesseract-ocr-service/Dockerfile"
  ocr_tessdata_file   = "${path.module}/modules/tesseract/tessdata/por.traineddata"
  api_replicas        = 0
  enable_ingress      = var.tesseract_enable_ingress && var.domain_name != ""

  providers = {
    kubernetes = kubernetes
  }

  depends_on = [
    module.k3d_cluster,
    module.networking,
    module.traefik
  ]
}

# --- ESTRUTURA PARA O GITLAB ---

resource "kubernetes_namespace_v1" "gitlab" {
  metadata {
    name = "gitlab"
  }
  depends_on = [module.k3d_cluster]
}

# Aguarda o CRD do Traefik estar pronto
resource "null_resource" "wait_for_traefik_middleware_crd" {
  depends_on = [module.traefik]

  provisioner "local-exec" {
    command = "kubectl wait --for=condition=established --timeout=120s crd/middlewares.traefik.io"
    environment = {
      KUBECONFIG = "${path.cwd}/.k3d_kubeconfig"
    }
  }
}

# Delay para propagação do CRD
resource "time_sleep" "wait_for_crd_propagation" {
  depends_on      = [null_resource.wait_for_traefik_middleware_crd]
  create_duration = "30s"
}

resource "null_resource" "wait_for_traefik_ingressroutetcp_crd" {
  depends_on = [module.traefik]

  provisioner "local-exec" {
    command = "kubectl wait --for=condition=established --timeout=120s crd/ingressroutetcps.traefik.io"
    environment = {
      KUBECONFIG = "${path.cwd}/.k3d_kubeconfig"
    }
  }
}

resource "kubectl_manifest" "meu_album_postgres_tcp_route" {
  depends_on = [
    module.postgres,
    module.traefik,
    null_resource.wait_for_traefik_ingressroutetcp_crd
  ]

  yaml_body = <<-YAML
    apiVersion: traefik.io/v1alpha1
    kind: IngressRouteTCP
    metadata:
      name: meu-album-postgres
      namespace: ${module.traefik.namespace}
    spec:
      entryPoints:
        - postgres
      routes:
        - match: HostSNI(`*`)
          services:
            - name: ${module.postgres.meu_album_postgres_service_name}
              namespace: ${module.postgres.meu_album_postgres_namespace}
              port: 5432
  YAML
}

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
  depends_on = [
    kubernetes_namespace_v1.gitlab,
    module.traefik,
    time_sleep.wait_for_crd_propagation
  ]
}

# Módulo GitLab (Ajustado para 9.0.0 / GitLab 18.0)
module "gitlab" {
  source = "./modules/gitlab"

  chart_version                 = "9.0.0"
  postgres_password_secret_data = module.postgres.postgres_password_secret_data

  domain_name     = var.domain_name
  namespace       = kubernetes_namespace_v1.gitlab.metadata[0].name
  trusted_proxies = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "127.0.0.1"]

  root_password               = var.gitlab_root_password
  minio_access_key            = var.minio_access_key
  minio_secret_key            = var.minio_secret_key
  redis_password              = var.redis_password
  runner_authentication_token = var.gitlab_runner_token
  traefik_service_cluster_ip  = module.traefik.service_cluster_ip

  providers = {
    helm       = helm
    kubernetes = kubernetes
  }

  depends_on = [
    module.traefik,
    module.minio,
    module.postgres,
    module.cloudflare,
    kubernetes_manifest.traefik_middleware,
    kubernetes_namespace_v1.gitlab
  ]
}

# --- Cloudflare Tunnel (Ajustado com ordem de precedência) ---

module "cloudflare" {
  source                = "./modules/cloudflare"
  domain_name           = var.domain_name
  cloudflare_account_id = var.cloudflare_account_id
  cloudflare_zone_id    = var.cloudflare_zone_id
  tunnel_name           = "k3d-tunnel"

  services = [
    { hostname = "traefik", service = "http://traefik.traefik.svc.cluster.local:80" },
    { hostname = "gitlab", service = "http://traefik.traefik.svc.cluster.local:80" },
    { hostname = "registry", service = "http://traefik.traefik.svc.cluster.local:80" },
    { hostname = "minio", service = "http://traefik.traefik.svc.cluster.local:80" },
    { hostname = "minio-console", service = "http://traefik.traefik.svc.cluster.local:80" },
    { hostname = "authentik", service = "http://traefik.traefik.svc.cluster.local:80" },
    { hostname = var.tesseract_hostname, service = "http://traefik.traefik.svc.cluster.local:80" },
    { hostname = "db", service = "tcp://${module.postgres.meu_album_postgres_service_name}.${module.postgres.meu_album_postgres_namespace}.svc.cluster.local:5432" },

    { hostname = "", service = "http://traefik.traefik.svc.cluster.local:80" },

    { hostname = "*", service = "http://traefik.traefik.svc.cluster.local:80" }
  ]

  providers = {
    cloudflare = cloudflare
    kubernetes = kubernetes
  }

  depends_on = [module.k3d_cluster, module.networking, module.tesseract]
}
