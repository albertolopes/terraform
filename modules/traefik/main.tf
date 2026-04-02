# Namespace para o Traefik
resource "kubernetes_namespace_v1" "traefik" {
  metadata {
    name = "traefik"
    labels = {
      "app.kubernetes.io/name" = "traefik"
    }
  }
}

# Service Account
resource "kubernetes_service_account_v1" "traefik" {
  metadata {
    name      = "traefik"
    namespace = kubernetes_namespace_v1.traefik.metadata[0].name
  }

  depends_on = [kubernetes_namespace_v1.traefik]
}

# ClusterRole para Traefik
resource "kubernetes_cluster_role_v1" "traefik" {
  metadata {
    name = "traefik"
  }

  rule {
    api_groups = [""]
    resources  = ["services", "endpoints", "secrets", "configmaps", "pods", "nodes"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["ingresses", "ingressclasses"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["traefik.io"]
    resources  = [
      "middlewares",
      "middlewaretcps",
      "ingressroutes",
      "ingressroutetcps",
      "ingressrouteudps",
      "tlsoptions",
      "tlsstores",
      "serverstransports",
      "serverstransporttcps",
      "traefikservices"
    ]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["discovery.k8s.io"]
    resources  = ["endpointslices"]
    verbs      = ["get", "list", "watch"]
  }
}

# ClusterRoleBinding
resource "kubernetes_cluster_role_binding_v1" "traefik" {
  metadata {
    name = "traefik"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.traefik.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.traefik.metadata[0].name
    namespace = kubernetes_namespace_v1.traefik.metadata[0].name
  }

  depends_on = [
    kubernetes_cluster_role_v1.traefik,
    kubernetes_service_account_v1.traefik
  ]
}

# ConfigMap do Traefik
resource "kubernetes_config_map_v1" "traefik" {
  metadata {
    name      = "traefik-config"
    namespace = kubernetes_namespace_v1.traefik.metadata[0].name
  }

  data = {
    "traefik.yml" = <<-EOT
      global:
        sendAnonymousUsage: false

      api:
        dashboard: true
        insecure: true

      ping:
        entryPoint: traefik

      entryPoints:
        web:
          address: ":80"
          http:
            redirections:
              entryPoint:
                to: websecure
                scheme: https
                permanent: true
        websecure:
          address: ":443"
          http:
            tls: {}
        traefik:
          address: ":8080"

      providers:
        kubernetesCRD:
          allowCrossNamespace: true
        kubernetesIngress:
          allowExternalNameServices: true
          ingressClass: traefik

      log:
        level: INFO
        format: json

      accessLog:
        format: json
    EOT
  }

  depends_on = [kubernetes_namespace_v1.traefik]
}

# Apply Traefik CRDs
resource "null_resource" "traefik_crds" {
  triggers = {
    namespace_name = kubernetes_namespace_v1.traefik.metadata[0].name
  }

  provisioner "local-exec" {
    command = "kubectl apply -f https://raw.githubusercontent.com/traefik/traefik/v3.3/docs/content/reference/dynamic-configuration/kubernetes-crd-definition-v1.yml"
    environment = {
      KUBECONFIG = "${path.cwd}/.k3d_kubeconfig"
    }
  }

  depends_on = [kubernetes_namespace_v1.traefik]
}

# Deployment do Traefik
resource "kubernetes_deployment_v1" "traefik" {
  metadata {
    name      = "traefik"
    namespace = kubernetes_namespace_v1.traefik.metadata[0].name
    labels = {
      "app.kubernetes.io/name"    = "traefik"
      "app.kubernetes.io/version" = "v3.3"
    }
  }

  spec {
    replicas = var.replicas

    selector {
      match_labels = {
        app = "traefik"
      }
    }

    template {
      metadata {
        labels = {
          app = "traefik"
        }
        annotations = {
          "checksum/config" = sha256(kubernetes_config_map_v1.traefik.data["traefik.yml"])
        }
      }

      spec {
        service_account_name = kubernetes_service_account_v1.traefik.metadata[0].name

        container {
          name  = "traefik"
          image = "traefik:v3.3"

          args = [
            "--configfile=/config/traefik.yml",
            "--providers.kubernetesingress",
            "--providers.kubernetescrd",
            "--providers.kubernetesingress.ingressclass=traefik",
            "--ping",
          ]

          port {
            name           = "web"
            container_port = 80
          }

          port {
            name           = "websecure"
            container_port = 443
          }

          port {
            name           = "admin"
            container_port = 8080
          }

          volume_mount {
            name       = "config"
            mount_path = "/config"
          }

          volume_mount {
            name       = "data"
            mount_path = "/data"
          }

          liveness_probe {
            http_get {
              path = "/ping"
              port = 8080
            }
            initial_delay_seconds = 10
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/ping"
              port = 8080
            }
            initial_delay_seconds = 10
            period_seconds        = 10
          }

          resources {
            requests = {
              cpu    = var.cpu_requests
              memory = var.memory_requests
            }
            limits = {
              cpu    = var.cpu_limits
              memory = var.memory_limits
            }
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map_v1.traefik.metadata[0].name
          }
        }

        volume {
          name = "data"
          empty_dir {}
        }
      }
    }
  }

  depends_on = [
    kubernetes_config_map_v1.traefik,
    kubernetes_service_account_v1.traefik,
    null_resource.traefik_crds
  ]
}

# IngressClass para Traefik
resource "kubernetes_ingress_class_v1" "traefik" {
  metadata {
    name = "traefik"
    annotations = {
      "ingressclass.kubernetes.io/is-default-class" = "true"
    }
  }
  spec {
    controller = "traefik.io/ingress-controller"
  }
}

# Service LoadBalancer
resource "kubernetes_service_v1" "traefik" {
  metadata {
    name      = "traefik"
    namespace = kubernetes_namespace_v1.traefik.metadata[0].name
  }

  spec {
    type = "LoadBalancer"

    selector = {
      app = "traefik"
    }

    port {
      name        = "web"
      port        = 80
      target_port = 80
    }

    port {
      name        = "websecure"
      port        = 443
      target_port = 443
    }

    port {
      name        = "admin"
      port        = 8080
      target_port = 8080
    }
  }

  depends_on = [kubernetes_deployment_v1.traefik]
}

# Certificado SSL no namespace 'traefik'
resource "kubernetes_manifest" "traefik_certs" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "traefik-certs"
      namespace = kubernetes_namespace_v1.traefik.metadata[0].name
    }
    spec = {
      secretName = "traefik-certs"
      issuerRef = {
        name = "letsencrypt-cloudflare"
        kind = "ClusterIssuer"
      }
      dnsNames = [
        "traefik.${var.domain_name}"
      ]
    }
  }
}

# Secret para autenticação do dashboard
resource "kubernetes_secret_v1" "dashboard_auth" {
  count = var.enable_dashboard ? 1 : 0

  metadata {
    name      = "traefik-dashboard-auth"
    namespace = kubernetes_namespace_v1.traefik.metadata[0].name
  }

  data = {
    users = "${var.dashboard_user}:${var.dashboard_password}"
  }
  type = "Opaque"

  depends_on = [kubernetes_namespace_v1.traefik]
}

# Middleware para autenticação do dashboard
resource "kubernetes_manifest" "dashboard_auth" {
  count = var.enable_dashboard ? 1 : 0

  depends_on = [
    kubernetes_secret_v1.dashboard_auth,
    null_resource.traefik_crds
  ]
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "Middleware"
    metadata = {
      name      = "dashboard-auth"
      namespace = kubernetes_namespace_v1.traefik.metadata[0].name
    }
    spec = {
      basicAuth = {
        secret = "traefik-dashboard-auth"
      }
    }
  }
}

# Traefik IngressRoute para o Dashboard (NOMES LIMPIDAMENTE NOVOS)
resource "kubernetes_manifest" "traefik_dashboard_native" {
  count = var.enable_dashboard ? 1 : 0

  depends_on = [
    kubernetes_service_v1.traefik,
    kubernetes_manifest.dashboard_auth,
    kubernetes_ingress_class_v1.traefik,
    kubernetes_manifest.traefik_certs,
    null_resource.traefik_crds
  ]

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "traefik-dashboard-native" # Renomeado para forçar refresh
      namespace = kubernetes_namespace_v1.traefik.metadata[0].name
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [
        {
          match = "Host(`traefik.${var.domain_name}`) && (PathPrefix(`/dashboard`) || PathPrefix(`/api`))"
          kind  = "Rule"
          services = [
            {
              name = "api@internal"
              kind = "TraefikService"
            }
          ]
          middlewares = [
            {
              name      = "dashboard-auth"
              namespace = kubernetes_namespace_v1.traefik.metadata[0].name
            }
          ]
        }
      ]
      tls = {
        secretName = "traefik-certs"
      }
    }
  }
}
