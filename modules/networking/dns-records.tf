resource "kubernetes_ingress_v1" "external_dns_targets" {
  metadata {
    name      = "external-dns-targets"
    namespace = "traefik" # Coloquei no mesmo namespace do Traefik
    annotations = {
      "kubernetes.io/ingress.class" = "traefik"
      # Força a criação de CNAMEs apontando para o Funnel
      "external-dns.alpha.kubernetes.io/target" = var.tailscale_funnel_url
      # Desabilita o proxy do Cloudflare (nuvem cinza)
      "external-dns.alpha.kubernetes.io/cloudflare-proxied" = "false"
    }
  }

  spec {
    ingress_class_name = "traefik"
    # Lista de todos os domínios que você quer criar no Cloudflare
    rule {
      host = "keycloak.${var.domain_name}"
      http {
        path {
          path = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "traefik"
              port {
                number = 80
              }
            }
          }
        }
      }
    }
    rule {
      host = "minio.${var.domain_name}"
      http {
        path {
          path = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "traefik"
              port {
                number = 80
              }
            }
          }
        }
      }
    }
    rule {
      host = "minio-console.${var.domain_name}"
      http {
        path {
          path = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "traefik"
              port {
                number = 80
              }
            }
          }
        }
      }
    }
    rule {
      host = "api.${var.domain_name}"
      http {
        path {
          path = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "traefik"
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }
}
