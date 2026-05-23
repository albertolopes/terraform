terraform {
  required_providers {
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }
}

locals {
  api_labels = {
    app = "tesseract-api"
  }

  tesseract_labels = {
    app = "tesseract-ocr"
  }

  public_host         = "${var.hostname}.${var.domain_name}"
  public_service_name = var.api_replicas > 0 ? kubernetes_service_v1.api.metadata[0].name : kubernetes_service_v1.tesseract_ocr.metadata[0].name
  public_service_port = var.api_replicas > 0 ? 8080 : 8081
}

resource "kubernetes_namespace_v1" "tesseract" {
  metadata {
    name = var.namespace
  }
}

resource "null_resource" "build_import_tesseract_ocr_image" {
  count = var.ocr_build_context == null ? 0 : 1

  triggers = {
    image         = var.tesseract_ocr_image
    build_context = var.ocr_build_context
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      docker build --platform linux/amd64 -t ${var.tesseract_ocr_image} ${var.ocr_build_context}
      k3d image import --cluster ${var.k3d_cluster_name} ${var.tesseract_ocr_image}
    EOT
  }
}

resource "null_resource" "build_import_api_image" {
  count = var.api_build_context == null ? 0 : 1

  triggers = {
    image         = var.api_image
    build_context = var.api_build_context
    dockerfile    = var.api_dockerfile == null ? "" : var.api_dockerfile
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      docker build --platform linux/amd64 ${var.api_dockerfile == null ? "" : "-f ${var.api_dockerfile}"} -t ${var.api_image} ${var.api_build_context}
      k3d image import --cluster ${var.k3d_cluster_name} ${var.api_image}
    EOT
  }
}

resource "kubernetes_deployment_v1" "tesseract_ocr" {
  metadata {
    name      = "tesseract-ocr"
    namespace = kubernetes_namespace_v1.tesseract.metadata[0].name
    labels    = local.tesseract_labels
  }

  spec {
    replicas = var.tesseract_replicas

    selector {
      match_labels = local.tesseract_labels
    }

    template {
      metadata {
        labels = local.tesseract_labels
      }

      spec {
        container {
          name              = "tesseract-ocr"
          image             = var.tesseract_ocr_image
          image_pull_policy = var.image_pull_policy

          env {
            name  = "TESSERACT_TIMEOUT_SECONDS"
            value = tostring(var.tesseract_timeout_seconds)
          }

          env {
            name  = "MAX_BODY_BYTES"
            value = tostring(var.max_body_bytes)
          }

          port {
            name           = "http"
            container_port = 8081
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 8081
            }
            initial_delay_seconds = 20
            period_seconds        = 10
            timeout_seconds       = 3
            failure_threshold     = 5
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = 8081
            }
            initial_delay_seconds = 5
            period_seconds        = 10
            timeout_seconds       = 3
            failure_threshold     = 5
          }

          resources {
            requests = {
              cpu    = "250m"
              memory = "512Mi"
            }
            limits = {
              cpu    = "1500m"
              memory = "2Gi"
            }
          }
        }
      }
    }
  }

  depends_on = [
    null_resource.build_import_tesseract_ocr_image
  ]
}

resource "kubernetes_service_v1" "tesseract_ocr" {
  metadata {
    name      = "tesseract-ocr"
    namespace = kubernetes_namespace_v1.tesseract.metadata[0].name
    labels    = local.tesseract_labels
  }

  spec {
    selector = local.tesseract_labels

    port {
      name        = "http"
      port        = 8081
      target_port = 8081
    }

    type = "ClusterIP"
  }
}

resource "kubernetes_deployment_v1" "api" {
  metadata {
    name      = "tesseract-api"
    namespace = kubernetes_namespace_v1.tesseract.metadata[0].name
    labels    = local.api_labels
  }

  spec {
    replicas = var.api_replicas

    selector {
      match_labels = local.api_labels
    }

    template {
      metadata {
        labels = local.api_labels
      }

      spec {
        init_container {
          name    = "wait-for-tesseract-ocr"
          image   = "python:3.12-alpine"
          command = ["python", "-c"]
          args = [
            "import time, urllib.request\nurl='http://tesseract-ocr:8081/health'\nwhile True:\n    try:\n        urllib.request.urlopen(url, timeout=3).read()\n        break\n    except Exception:\n        time.sleep(2)\n"
          ]
        }

        container {
          name              = "tesseract-api"
          image             = var.api_image
          image_pull_policy = var.image_pull_policy

          env {
            name  = "OCR_TESSERACT_URL"
            value = "http://tesseract-ocr:8081"
          }

          port {
            name           = "http"
            container_port = 8080
          }

          readiness_probe {
            tcp_socket {
              port = 8080
            }
            initial_delay_seconds = 10
            period_seconds        = 10
            timeout_seconds       = 3
            failure_threshold     = 6
          }

          liveness_probe {
            tcp_socket {
              port = 8080
            }
            initial_delay_seconds = 30
            period_seconds        = 20
            timeout_seconds       = 5
            failure_threshold     = 3
          }

          resources {
            requests = {
              cpu    = "250m"
              memory = "512Mi"
            }
            limits = {
              cpu    = "1000m"
              memory = "1Gi"
            }
          }
        }
      }
    }
  }

  depends_on = [
    null_resource.build_import_api_image,
    kubernetes_deployment_v1.tesseract_ocr,
    kubernetes_service_v1.tesseract_ocr
  ]
}

resource "kubernetes_service_v1" "api" {
  metadata {
    name      = "tesseract-api"
    namespace = kubernetes_namespace_v1.tesseract.metadata[0].name
    labels    = local.api_labels
  }

  spec {
    selector = local.api_labels

    port {
      name        = "http"
      port        = 8080
      target_port = 8080
    }

    type = "ClusterIP"
  }
}

resource "kubernetes_manifest" "api_tls_certificate" {
  count = var.enable_ingress ? 1 : 0

  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "tesseract-tls"
      namespace = kubernetes_namespace_v1.tesseract.metadata[0].name
    }
    spec = {
      secretName = "tesseract-tls"
      issuerRef = {
        name = "letsencrypt-cloudflare"
        kind = "ClusterIssuer"
      }
      dnsNames = [
        local.public_host
      ]
    }
  }
}

resource "kubernetes_ingress_v1" "api" {
  count = var.enable_ingress ? 1 : 0

  metadata {
    name      = "tesseract"
    namespace = kubernetes_namespace_v1.tesseract.metadata[0].name
    annotations = {
      "kubernetes.io/ingress.class"                      = "traefik"
      "traefik.ingress.kubernetes.io/router.entrypoints" = "web,websecure"
    }
  }

  spec {
    ingress_class_name = "traefik"

    rule {
      host = local.public_host

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = local.public_service_name

              port {
                number = local.public_service_port
              }
            }
          }
        }
      }
    }

    tls {
      hosts       = [local.public_host]
      secret_name = "tesseract-tls"
    }
  }

  depends_on = [
    kubernetes_service_v1.api,
    kubernetes_service_v1.tesseract_ocr,
    kubernetes_manifest.api_tls_certificate
  ]
}
