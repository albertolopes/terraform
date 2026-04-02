variable "domain_name" {
  description = "Base domain name"
  type        = string
}

variable "cloudflare_api_token" {
  description = "Cloudflare API Token for DNS-01 challenge"
  type        = string
  sensitive   = true
}

variable "tailscale_funnel_url" {
  description = "The Tailscale Funnel URL to point CNAME records to"
  type        = string
  default     = "avocado.tail799250.ts.net"
}

# --- Cert-Manager (Helm) ---
resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  namespace  = "cert-manager"
  create_namespace = true
  version    = "v1.14.4"

  set = [
    {
      name  = "installCRDs"
      value = "true"
    },
    {
      name  = "podDnsPolicy"
      value = "None"
    },
    {
      name  = "podDnsConfig.nameservers[0]"
      value = "8.8.8.8"
    }
  ]
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
resource "kubernetes_manifest" "letsencrypt_issuer" {
  depends_on = [
    kubernetes_secret_v1.cloudflare_api_token,
    null_resource.wait_for_cert_manager_crds
  ]
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-cloudflare"
    }
    spec = {
      acme = {
        email  = "admin@${var.domain_name}"
        server = "https://acme-v02.api.letsencrypt.org/directory"
        privateKeySecretRef = {
          name = "letsencrypt-cloudflare-account-key"
        }
        solvers = [
          {
            dns01 = {
              cloudflare = {
                apiTokenSecretRef = {
                  name = kubernetes_secret_v1.cloudflare_api_token.metadata[0].name
                  key  = "api-token"
                }
              }
            }
          }
        ]
      }
    }
  }
}

# --- Certificate (Let's Encrypt) ---
resource "kubernetes_manifest" "avocado_cert" {
  depends_on = [kubernetes_manifest.letsencrypt_issuer]
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "avocado-public-cert"
      namespace = "default"
    }
    spec = {
      secretName = "nginx-certs" # Mesmo nome que o Nginx já usa
      issuerRef = {
        name = "letsencrypt-cloudflare"
        kind = "ClusterIssuer"
      }
      dnsNames = [
        var.domain_name,
        "*.${var.domain_name}"
      ]
    }
  }
}
