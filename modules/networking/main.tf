variable "domain_name" {
  description = "Base domain name"
  type        = string
}



resource "kubernetes_ingress_v1" "main" {
  metadata {
    name = "main-ingress"
    annotations = {
      "kubernetes.io/ingress.class" = "nginx"
    }
  }
  spec {
    rule {
      host = "keycloak.${var.domain_name}"
      http {
        path {
          path = "/"
          backend {
            service {
              name = "keycloak"
              port {
                number = 8080
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
          backend {
            service {
              name = "minio"
              port {
                number = 9000
              }
            }
          }
        }
      }
    }
    rule {
      host = "nginx.${var.domain_name}"
      http {
        path {
          path = "/"
          backend {
            service {
              name = "nginx"
              port {
                number = 80
              }
            }
          }
        }
      }
    }
    # Opcional: domínio raiz apontando para o nginx
    rule {
      host = var.domain_name
      http {
        path {
          path = "/"
          backend {
            service {
              name = "nginx"
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
