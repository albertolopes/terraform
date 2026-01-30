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
  }
}

provider "kubernetes" {
  config_path = "${path.module}/.k3d_kubeconfig"
}

provider "helm" {
  kubernetes = {
    config_path = "${path.module}/.k3d_kubeconfig"
  }
}
