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
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = ">= 4.0.0"
    }
    http = {
      source  = "hashicorp/http"
      version = ">= 3.0.0"
    }
  }
}

locals {
  kubeconfig_path       = var.kubernetes_config_path == null ? "${path.module}/.k3d_kubeconfig" : var.kubernetes_config_path
  kubernetes_host_value = var.kubernetes_host == null ? "" : var.kubernetes_host
  kubernetes_host       = contains(["", "0.0.0.0:6443", "https://0.0.0.0:6443"], local.kubernetes_host_value) ? "https://127.0.0.1:6443" : var.kubernetes_host
}

provider "kubernetes" {
  host        = local.kubernetes_host
  config_path = local.kubeconfig_path
  insecure    = true
}

provider "helm" {
  kubernetes {
    host        = local.kubernetes_host
    config_path = local.kubeconfig_path
    insecure    = true
  }
}

provider "kubectl" {
  host        = local.kubernetes_host
  config_path = local.kubeconfig_path
  insecure    = true
}

provider "docker" {}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
