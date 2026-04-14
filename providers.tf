# providers.tf

terraform {
  required_providers {
    kubectl = {
      source  = "alekc/kubectl"
      version = ">= 2.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9"
    }
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
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.0.0"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

locals {
  kubeconfig_path = "${path.module}/.k3d_kubeconfig"
}

provider "kubernetes" {
  config_path = fileexists(local.kubeconfig_path) ? local.kubeconfig_path : null
}

provider "helm" {
  kubernetes {
    config_path = fileexists(local.kubeconfig_path) ? local.kubeconfig_path : null
  }
}

provider "docker" {}