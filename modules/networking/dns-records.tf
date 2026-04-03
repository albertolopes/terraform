resource "kubernetes_ingress_v1" "external_dns_targets" {
  metadata {
    name      = "external-dns-targets"
    namespace = "traefik"
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
    # Agora centralizado no domínio principal para suportar o Tailscale Funnel
    rule {
      host = var.domain_name
      http {
        path {
          path = "/keycloak"
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
        path {
          path = "/minio"
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
        path {
          path = "/console"
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
        path {
          path = "/traefik"
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
