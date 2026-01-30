resource "helm_release" "ingress_nginx" {
  depends_on       = [null_resource.k3d_cluster]
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true
  wait             = true
  timeout          = 300
  cleanup_on_fail  = true
}

resource "kubernetes_ingress_v1" "main_ingress" {
  depends_on = [helm_release.ingress_nginx]
  metadata {
    name = "main-ingress"
    annotations = {
      "kubernetes.io/ingress.class" = "nginx"
    }
  }
  spec {
    ingress_class_name = "nginx"
    rule {
      host = "minio.${var.domain_name}"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
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
      host = "minio-console.${var.domain_name}"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "minio"
              port {
                number = 9001
              }
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_ingress_v1" "keycloak_ingress" {
  depends_on = [kubernetes_service_v1.keycloak]

  metadata {
    name = "keycloak-ingress"
    annotations = {
      "nginx.ingress.kubernetes.io/proxy-buffer-size"    = "128k"
      "nginx.ingress.kubernetes.io/proxy-buffers-number" = "4"
      "nginx.ingress.kubernetes.io/proxy-read-timeout"   = "900"
      "nginx.ingress.kubernetes.io/proxy-send-timeout"   = "900"
      "nginx.ingress.kubernetes.io/ssl-redirect"         = "false"
    }
  }

  spec {
    ingress_class_name = "nginx"

    rule {
      host = "keycloak.${var.domain_name}"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
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
  }
}
