terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }
}

resource "random_password" "tunnel_secret" {
  length  = 64
  special = false
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "k3d_tunnel" {
  account_id = var.cloudflare_account_id
  name       = var.tunnel_name
  secret     = base64encode(random_password.tunnel_secret.result)
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "k3d_config" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.k3d_tunnel.id

  config {
    dynamic "ingress_rule" {
      for_each = var.services
      content {
        hostname = ingress_rule.value.hostname == "" ? var.domain_name : "${ingress_rule.value.hostname}.${var.domain_name}"
        service  = ingress_rule.value.service
      }
    }

    # Regra de Fallback (Obrigatória)
    ingress_rule {
      service = "http_status:404"
    }
  }
}

# 4. Criar os registros CNAME no Cloudflare
resource "cloudflare_record" "tunnel_cnames" {
  for_each = { for s in var.services : s.hostname => s }

  zone_id         = var.cloudflare_zone_id
  # Se o hostname for vazio (raiz), o Cloudflare espera "@" ou o nome do domínio.
  name            = each.value.hostname == "" ? "@" : each.value.hostname
  type            = "CNAME"
  content         = "${cloudflare_zero_trust_tunnel_cloudflared.k3d_tunnel.id}.cfargotunnel.com"
  proxied         = true
  allow_overwrite = true
}

# 5. Criar o segredo do túnel no Kubernetes
resource "kubernetes_secret_v1" "tunnel_token" {
  metadata {
    name      = "cloudflare-tunnel-token"
    namespace = "kube-system"
  }

  data = {
    token = cloudflare_zero_trust_tunnel_cloudflared.k3d_tunnel.tunnel_token
  }
}

# 6. Deploy do agente cloudflared no Cluster
resource "kubernetes_deployment_v1" "cloudflared" {
  metadata {
    name      = "cloudflared"
    namespace = "kube-system"
    labels = {
      app = "cloudflared"
    }
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "cloudflared"
      }
    }

    template {
      metadata {
        labels = {
          app = "cloudflared"
        }
      }

      spec {
        container {
          name  = "cloudflared"
          image = "cloudflare/cloudflared:latest"
          args  = ["tunnel", "--no-autoupdate", "--metrics", "0.0.0.0:2000", "--protocol", "http2", "run"]

          env {
            name = "TUNNEL_TOKEN"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.tunnel_token.metadata[0].name
                key  = "token"
              }
            }
          }

          liveness_probe {
            http_get {
              path = "/ready"
              port = 2000
            }
            initial_delay_seconds = 10
            period_seconds        = 10
          }
        }
      }
    }
  }
}