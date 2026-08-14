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
  kubeconfig_path = var.kubernetes_config_path == null ? "${path.module}/.k3d_kubeconfig" : var.kubernetes_config_path
  kubeconfig      = yamldecode(file(local.kubeconfig_path))

  kubeconfig_cluster = local.kubeconfig.clusters[0].cluster
  kubeconfig_user    = local.kubeconfig.users[0].user

  kubernetes_host_source = var.kubernetes_host != null && var.kubernetes_host != "" ? var.kubernetes_host : local.kubeconfig_cluster.server
  kubernetes_host        = replace(local.kubernetes_host_source, "https://0.0.0.0:", "https://127.0.0.1:")

  kubernetes_insecure           = try(local.kubeconfig_cluster["insecure-skip-tls-verify"], false)
  kubernetes_ca_certificate     = try(base64decode(local.kubeconfig_cluster["certificate-authority-data"]), null)
  kubernetes_client_certificate = base64decode(local.kubeconfig_user["client-certificate-data"])
  kubernetes_client_key         = base64decode(local.kubeconfig_user["client-key-data"])
}

provider "kubernetes" {
  host                   = local.kubernetes_host
  insecure               = local.kubernetes_insecure
  cluster_ca_certificate = local.kubernetes_ca_certificate
  client_certificate     = local.kubernetes_client_certificate
  client_key             = local.kubernetes_client_key
}

provider "helm" {
  kubernetes {
    host                   = local.kubernetes_host
    insecure               = local.kubernetes_insecure
    cluster_ca_certificate = local.kubernetes_ca_certificate
    client_certificate     = local.kubernetes_client_certificate
    client_key             = local.kubernetes_client_key
  }
}

provider "kubectl" {
  load_config_file       = false
  host                   = local.kubernetes_host
  insecure               = local.kubernetes_insecure
  cluster_ca_certificate = local.kubernetes_ca_certificate
  client_certificate     = local.kubernetes_client_certificate
  client_key             = local.kubernetes_client_key
}

provider "docker" {}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
