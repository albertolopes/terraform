terraform {
  required_providers {
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
    helm = {
      source = "hashicorp/helm"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = ">= 2.0"
    }
  }
}

variable "domain_name" {
  description = "Base domain name"
  type        = string
}

variable "cloudflare_api_token" {
  description = "Cloudflare API Token for DNS-01 challenge"
  type        = string
  sensitive   = true
}

# --- Cert-Manager (Helm) ---
resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  namespace  = "cert-manager"
  create_namespace = true
  version    = "v1.14.4"
  timeout    = 1800

  set {
    name  = "installCRDs"
    value = "true"
  }
  
  set {
    name  = "podDnsPolicy"
    value = "None"
  }
  
  set {
    name  = "podDnsConfig.nameservers[0]"
    value = "8.8.8.8"
  }
}

# Wait for Cert-Manager CRDs to be ready
resource "null_resource" "wait_for_cert_manager_crds" {
  depends_on = [helm_release.cert_manager]

  provisioner "local-exec" {
    command = "kubectl wait --for=condition=established --timeout=60s crd/clusterissuers.cert-manager.io"
    environment = {
      KUBECONFIG = "${path.cwd}/.k3d_kubeconfig"
    }
  }
}

# --- Cloudflare API Token Secret ---
resource "kubernetes_secret_v1" "cloudflare_api_token" {
  depends_on = [helm_release.cert_manager]
  metadata {
    name      = "cloudflare-api-token-secret"
    namespace = "cert-manager"
  }

  data = {
    "api-token" = var.cloudflare_api_token
  }
}

# --- ClusterIssuer (Let's Encrypt + DNS-01) ---
resource "kubectl_manifest" "letsencrypt_issuer" {
  depends_on = [
    kubernetes_secret_v1.cloudflare_api_token,
    null_resource.wait_for_cert_manager_crds
  ]
  yaml_body = <<-YAML
    apiVersion: cert-manager.io/v1
    kind: ClusterIssuer
    metadata:
      name: letsencrypt-cloudflare
    spec:
      acme:
        email: admin@${var.domain_name}
        server: https://acme-v02.api.letsencrypt.org/directory
        privateKeySecretRef:
          name: letsencrypt-cloudflare-account-key
        solvers:
          - dns01:
              cloudflare:
                apiTokenSecretRef:
                  name: cloudflare-api-token-secret
                  key: api-token
  YAML
}

# --- Certificate (Let's Encrypt) ---
resource "kubectl_manifest" "avocadotech_cert" {
  depends_on = [kubectl_manifest.letsencrypt_issuer]
  yaml_body = <<-YAML
    apiVersion: cert-manager.io/v1
    kind: Certificate
    metadata:
      name: avocadotech-public-cert
      namespace: default
    spec:
      secretName: nginx-certs
      issuerRef:
        name: letsencrypt-cloudflare
        kind: ClusterIssuer
      dnsNames:
        - ${var.domain_name}
        - "*.${var.domain_name}"
  YAML
}
