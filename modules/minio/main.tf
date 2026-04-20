# main.tf (raiz do projeto)

terraform {
  required_providers {
    helm = {
      source = "hashicorp/helm"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

# --- Variáveis ---
variable "domain_name" {
  description = "Base domain name"
  type        = string
  default     = "tail799250.ts.net"
}

variable "gitlab_root_password" {
  description = "Senha inicial do root do GitLab"
  type        = string
  sensitive   = true
  default     = "changeme123"
}

variable "minio_access_key" {
  description = "MinIO access key"
  type        = string
  default     = "minioadmin"
}

variable "minio_secret_key" {
  description = "MinIO secret key"
  type        = string
  sensitive   = true
  default     = "minioadmin123"
}

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

# --- Banco de Dados PostgreSQL ---
module "postgres" {
  source = "./modules/postgres"

  providers = {
    kubernetes = kubernetes
  }

  depends_on = [module.k3d_cluster]
}

# --- MinIO Object Storage (inline) ---
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
  depends_on      = [kubernetes_secret_v1.minio_credentials]
  name            = "minio"
  repository      = "https://charts.bitnami.com/bitnami"
  chart           = "minio"
  namespace       = "default"
  cleanup_on_fail = true
  wait            = true
  timeout         = 600

  values = [
    <<-YAML
    auth:
      existingSecret: minio-credentials

    service:
      type: ClusterIP

    defaultBuckets:
      - terraform-state
      - gitlab-lfs
      - gitlab-artifacts
      - gitlab-uploads
      - gitlab-packages

    ingress:
      enabled: true
      ingressClassName: traefik
      hostname: minio.${var.domain_name}
      path: /

    extraEnvVars:
      - name: MINIO_BROWSER_REDIRECT_URL
        value: https://minio.${var.domain_name}

    resources:
      requests:
        memory: 256Mi
        cpu: 100m
      limits:
        memory: 512Mi
        cpu: 500m

    persistence:
      enabled: true
      size: 10Gi
    YAML
  ]
}

# --- GitLab ---
module "gitlab" {
  source = "./modules/gitlab"

  namespace        = "gitlab"
  domain_name      = "gitlab.${var.domain_name}"
  root_password    = var.gitlab_root_password
  minio_access_key = var.minio_access_key
  minio_secret_key = var.minio_secret_key

  providers = {
    helm       = helm
    kubernetes = kubernetes
    kubectl    = kubectl
  }

  depends_on = [module.postgres, module.traefik, helm_release.minio]
}

# --- Outputs ---
output "gitlab_url" {
  value = "http://gitlab.${var.domain_name}"
}

output "gitlab_root_password" {
  value     = var.gitlab_root_password
  sensitive = true
}

output "minio_url" {
  value = "https://minio.${var.domain_name}"
}

output "gitlab_status_command" {
  value = "kubectl get pods -n gitlab -w"
}