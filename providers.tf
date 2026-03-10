terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.0.0"
    }
    random = {
      source = "hashicorp/random"
      version = ">= 3.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0.0"
    }
  }
}

locals {
  kubeconfig_path = "${path.module}/.k3d_kubeconfig"
  # Se o arquivo não existe, usamos um path que o Terraform ignorará durante a validação inicial do provider
  # mas que existe no sistema (como /dev/null) para evitar erro de 'stat' no plan.
  effective_config_path = fileexists(local.kubeconfig_path) ? local.kubeconfig_path : "/dev/null"
}

provider "kubernetes" {
  config_path = local.effective_config_path
}

provider "helm" {
  kubernetes = {
    config_path = local.effective_config_path
  }
}
