terraform {
  required_providers {
    cloudflare = {
      source = "cloudflare/cloudflare"
    }
    helm = {
      source = "hashicorp/helm"
    }
    kubectl = {
      source = "alekc/kubectl"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }
}

locals {
  mail_host       = "${var.mail_hostname}.${var.domain_name}"
  webmail_host    = "${var.webmail_hostname}.${var.domain_name}"
  admin_host      = "${var.admin_hostname}.${var.domain_name}"
  dns_mail_active = var.enable_dns_records && (var.mail_server_ipv4 != "" || var.mail_server_ipv6 != "")

  stalwart_values = {
    image = {
      repository = split(":", var.stalwart_image)[0]
      tag        = length(split(":", var.stalwart_image)) > 1 ? split(":", var.stalwart_image)[1] : "latest"
      pullPolicy = "IfNotPresent"
    }
    replicaCount = 1
    recoveryAdmin = {
      enabled  = true
      username = var.stalwart_recovery_admin_username
      password = var.stalwart_recovery_admin_password
    }
    config = {
      "@type" = "RocksDb"
      path    = "/var/lib/stalwart"
    }
    persistence = {
      enabled      = true
      accessMode   = "ReadWriteOnce"
      storageClass = "local-path"
      size         = var.stalwart_storage_size
    }
    resources = {
      requests = {
        cpu    = "250m"
        memory = "512Mi"
      }
      limits = {
        cpu    = "1000m"
        memory = "2Gi"
      }
    }
    ingress = {
      enabled   = false
      className = "traefik"
    }
  }
}

resource "kubernetes_namespace_v1" "mail" {
  metadata {
    name = var.namespace
  }
}

resource "helm_release" "stalwart" {
  name      = "stalwart"
  chart     = "${path.module}/stalwart"
  namespace = kubernetes_namespace_v1.mail.metadata[0].name
  timeout   = 900

  values = [
    yamlencode(local.stalwart_values)
  ]

  depends_on = [kubernetes_namespace_v1.mail]
}

resource "kubernetes_manifest" "stalwart_tls_certificate" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "stalwart-tls"
      namespace = kubernetes_namespace_v1.mail.metadata[0].name
    }
    spec = {
      secretName = "stalwart-tls"
      issuerRef = {
        name = "letsencrypt-cloudflare"
        kind = "ClusterIssuer"
      }
      dnsNames = [
        local.mail_host,
        local.admin_host
      ]
    }
  }
}

resource "kubernetes_ingress_v1" "stalwart_mail_http" {
  metadata {
    name      = "stalwart-mail-http"
    namespace = kubernetes_namespace_v1.mail.metadata[0].name
    annotations = {
      "kubernetes.io/ingress.class"                      = "traefik"
      "traefik.ingress.kubernetes.io/router.entrypoints" = "web,websecure"
    }
  }

  spec {
    ingress_class_name = "traefik"

    rule {
      host = local.mail_host

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = "stalwart"

              port {
                number = 80
              }
            }
          }
        }
      }
    }

    rule {
      host = local.admin_host

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = "stalwart"

              port {
                number = 8080
              }
            }
          }
        }
      }
    }

    tls {
      hosts       = [local.mail_host, local.admin_host]
      secret_name = "stalwart-tls"
    }
  }

  depends_on = [
    helm_release.stalwart,
    kubernetes_manifest.stalwart_tls_certificate
  ]
}

resource "kubernetes_persistent_volume_claim_v1" "snappymail_data" {
  metadata {
    name      = "snappymail-data"
    namespace = kubernetes_namespace_v1.mail.metadata[0].name
  }

  spec {
    access_modes = ["ReadWriteOnce"]

    resources {
      requests = {
        storage = var.snappymail_storage_size
      }
    }

    storage_class_name = "local-path"
  }

  wait_until_bound = false
}

resource "kubernetes_deployment_v1" "snappymail" {
  metadata {
    name      = "snappymail"
    namespace = kubernetes_namespace_v1.mail.metadata[0].name
    labels = {
      app = "snappymail"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "snappymail"
      }
    }

    template {
      metadata {
        labels = {
          app = "snappymail"
        }
      }

      spec {
        container {
          name  = "snappymail"
          image = var.snappymail_image

          port {
            name           = "http"
            container_port = 8888
          }

          liveness_probe {
            http_get {
              path = "/"
              port = 8888
            }
            initial_delay_seconds = 30
            period_seconds        = 20
            timeout_seconds       = 5
          }

          readiness_probe {
            http_get {
              path = "/"
              port = 8888
            }
            initial_delay_seconds = 10
            period_seconds        = 10
            timeout_seconds       = 5
          }

          volume_mount {
            name       = "data"
            mount_path = "/var/lib/snappymail"
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }
        }

        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.snappymail_data.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "snappymail" {
  metadata {
    name      = "snappymail"
    namespace = kubernetes_namespace_v1.mail.metadata[0].name
  }

  spec {
    selector = {
      app = "snappymail"
    }

    port {
      name        = "http"
      port        = 8888
      target_port = 8888
    }

    type = "ClusterIP"
  }
}

resource "kubernetes_manifest" "snappymail_tls_certificate" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "snappymail-tls"
      namespace = kubernetes_namespace_v1.mail.metadata[0].name
    }
    spec = {
      secretName = "snappymail-tls"
      issuerRef = {
        name = "letsencrypt-cloudflare"
        kind = "ClusterIssuer"
      }
      dnsNames = [
        local.webmail_host
      ]
    }
  }
}

resource "kubernetes_ingress_v1" "snappymail" {
  metadata {
    name      = "snappymail"
    namespace = kubernetes_namespace_v1.mail.metadata[0].name
    annotations = {
      "kubernetes.io/ingress.class"                      = "traefik"
      "traefik.ingress.kubernetes.io/router.entrypoints" = "web,websecure"
    }
  }

  spec {
    ingress_class_name = "traefik"

    rule {
      host = local.webmail_host

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service_v1.snappymail.metadata[0].name

              port {
                number = 8888
              }
            }
          }
        }
      }
    }

    tls {
      hosts       = [local.webmail_host]
      secret_name = "snappymail-tls"
    }
  }

  depends_on = [
    kubernetes_service_v1.snappymail,
    kubernetes_manifest.snappymail_tls_certificate
  ]
}

resource "kubectl_manifest" "stalwart_tcp_routes" {
  depends_on = [helm_release.stalwart]

  yaml_body = <<-YAML
    apiVersion: traefik.io/v1alpha1
    kind: IngressRouteTCP
    metadata:
      name: stalwart-mail-tcp
      namespace: ${kubernetes_namespace_v1.mail.metadata[0].name}
    spec:
      entryPoints:
        - smtp
      routes:
        - match: HostSNI(`*`)
          services:
            - name: stalwart
              namespace: ${kubernetes_namespace_v1.mail.metadata[0].name}
              port: 25
  YAML
}

resource "kubectl_manifest" "stalwart_smtps_tcp_route" {
  depends_on = [helm_release.stalwart]

  yaml_body = <<-YAML
    apiVersion: traefik.io/v1alpha1
    kind: IngressRouteTCP
    metadata:
      name: stalwart-smtps-tcp
      namespace: ${kubernetes_namespace_v1.mail.metadata[0].name}
    spec:
      entryPoints:
        - smtps
      routes:
        - match: HostSNI(`*`)
          services:
            - name: stalwart
              namespace: ${kubernetes_namespace_v1.mail.metadata[0].name}
              port: 465
  YAML
}

resource "kubectl_manifest" "stalwart_submission_tcp_route" {
  depends_on = [helm_release.stalwart]

  yaml_body = <<-YAML
    apiVersion: traefik.io/v1alpha1
    kind: IngressRouteTCP
    metadata:
      name: stalwart-submission-tcp
      namespace: ${kubernetes_namespace_v1.mail.metadata[0].name}
    spec:
      entryPoints:
        - submission
      routes:
        - match: HostSNI(`*`)
          services:
            - name: stalwart
              namespace: ${kubernetes_namespace_v1.mail.metadata[0].name}
              port: 587
  YAML
}

resource "kubectl_manifest" "stalwart_imaps_tcp_route" {
  depends_on = [helm_release.stalwart]

  yaml_body = <<-YAML
    apiVersion: traefik.io/v1alpha1
    kind: IngressRouteTCP
    metadata:
      name: stalwart-imaps-tcp
      namespace: ${kubernetes_namespace_v1.mail.metadata[0].name}
    spec:
      entryPoints:
        - imaps
      routes:
        - match: HostSNI(`*`)
          services:
            - name: stalwart
              namespace: ${kubernetes_namespace_v1.mail.metadata[0].name}
              port: 993
  YAML
}

resource "cloudflare_record" "mail_a" {
  count = var.enable_dns_records && var.mail_server_ipv4 != "" ? 1 : 0

  zone_id         = var.cloudflare_zone_id
  name            = var.mail_hostname
  type            = "A"
  content         = var.mail_server_ipv4
  ttl             = 300
  proxied         = false
  allow_overwrite = true
}

resource "cloudflare_record" "mail_aaaa" {
  count = var.enable_dns_records && var.mail_server_ipv6 != "" ? 1 : 0

  zone_id         = var.cloudflare_zone_id
  name            = var.mail_hostname
  type            = "AAAA"
  content         = var.mail_server_ipv6
  ttl             = 300
  proxied         = false
  allow_overwrite = true
}

resource "cloudflare_record" "mx" {
  count = local.dns_mail_active ? 1 : 0

  zone_id         = var.cloudflare_zone_id
  name            = "@"
  type            = "MX"
  content         = local.mail_host
  priority        = 10
  ttl             = 300
  allow_overwrite = true
}

resource "cloudflare_record" "spf" {
  count = local.dns_mail_active ? 1 : 0

  zone_id         = var.cloudflare_zone_id
  name            = "@"
  type            = "TXT"
  content         = "v=spf1 mx -all"
  ttl             = 300
  allow_overwrite = true
}

resource "cloudflare_record" "dmarc" {
  count = local.dns_mail_active ? 1 : 0

  zone_id         = var.cloudflare_zone_id
  name            = "_dmarc"
  type            = "TXT"
  content         = "v=DMARC1; p=quarantine; rua=mailto:postmaster@${var.domain_name}; adkim=s; aspf=s"
  ttl             = 300
  allow_overwrite = true
}
