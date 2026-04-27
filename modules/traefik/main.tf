# modules/traefik/main.tf

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
        websecure:
          address: ":443"
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

# Processar as CRDs localmente para evitar erros de planejamento
locals {
  # Divide o arquivo YAML em vários documentos e filtra blocos vazios
  traefik_crds = [for doc in split("---", file("${path.module}/crds.yaml")) : doc if trimspace(doc) != ""]
}

resource "kubectl_manifest" "traefik_crds" {
  for_each  = { for i, doc in local.traefik_crds : i => doc }
  yaml_body = each.value
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
    kubectl_manifest.traefik_crds
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

# Secret para autenticação do dashboard (SENHA: admin123 em hash BCrypt)
resource "kubernetes_secret_v1" "dashboard_auth" {
  metadata {
    name      = "traefik-dashboard-auth"
    namespace = kubernetes_namespace_v1.traefik.metadata[0].name
  }

  data = {
    users = "admin:${replace(bcrypt("admin123"), "$", "$$")}"
  }
  type = "Opaque"

  depends_on = [kubernetes_namespace_v1.traefik]
}

# Middleware para autenticação do dashboard
resource "kubectl_manifest" "dashboard_auth" {
  depends_on = [
    kubernetes_secret_v1.dashboard_auth,
    kubectl_manifest.traefik_crds
  ]
  yaml_body = <<-YAML
    apiVersion: traefik.io/v1alpha1
    kind: Middleware
    metadata:
      name: dashboard-auth
      namespace: ${kubernetes_namespace_v1.traefik.metadata[0].name}
    spec:
      basicAuth:
        secret: traefik-dashboard-auth
  YAML
}

  YAML
}

# Middleware para forçar header HTTPS (Resolve erro 422 no GitLab/Authentik)
resource "kubectl_manifest" "force_https_header" {
  depends_on = [kubectl_manifest.traefik_crds]
  yaml_body = <<-YAML
    apiVersion: traefik.io/v1alpha1
    kind: Middleware
    metadata:
      name: force-https-header
      namespace: ${kubernetes_namespace_v1.traefik.metadata[0].name}
    spec:
      headers:
        customRequestHeaders:
          X-Forwarded-Proto: "https"
  YAML
}

# Middleware StripPrefix (Para Minio, Console e Authentik)
resource "kubectl_manifest" "strip_prefixes" {
  depends_on = [kubectl_manifest.traefik_crds]
  yaml_body = <<-YAML
    apiVersion: traefik.io/v1alpha1
    kind: Middleware
    metadata:
      name: strip-prefixes
      namespace: ${kubernetes_namespace_v1.traefik.metadata[0].name}
    spec:
      stripPrefix:
        prefixes:
          - /minio
          - /console
          - /authentik
  YAML
}

# Traefik IngressRoute para Dashboard, Minio e Authentik
resource "kubectl_manifest" "traefik_dashboard_unified" {
  # Removido o count para simplificar, se habilitado via variável
  # No original era var.enable_dashboard ? 1 : 0
  
  depends_on = [
    kubernetes_service_v1.traefik,
    kubectl_manifest.dashboard_auth,
    kubectl_manifest.strip_prefixes,
    kubernetes_ingress_class_v1.traefik,
    kubectl_manifest.traefik_crds
  ]

  yaml_body = <<-YAML
    apiVersion: traefik.io/v1alpha1
    kind: IngressRoute
    metadata:
      name: main-ingressroute
      namespace: ${kubernetes_namespace_v1.traefik.metadata[0].name}
    spec:
      entryPoints:
        - web
        - websecure
      routes:
        - match: Host(`traefik.${var.domain_name}`) && (PathPrefix(`/dashboard`) || PathPrefix(`/api`))
          kind: Rule
          services:
            - name: api@internal
              kind: TraefikService
          middlewares:
            - name: dashboard-auth
              namespace: traefik
        - match: Host(`authentik.${var.domain_name}`)
          kind: Rule
          services:
            - name: authentik-server
              namespace: authentik
              port: 9000
          middlewares:
            - name: force-https-header
        - match: Host(`minio.${var.domain_name}`)
          kind: Rule
          services:
            - name: minio
              namespace: default
              port: 9000
          middlewares:
            - name: force-https-header
        - match: Host(`minio-console.${var.domain_name}`)
          kind: Rule
          services:
            - name: minio
              namespace: default
              port: 9001
          middlewares:
            - name: force-https-header
      tls:
        secretName: traefik-certs
  YAML
}

# Recurso Certificate para o Traefik
resource "kubectl_manifest" "traefik_cert" {
  yaml_body = <<-YAML
    apiVersion: cert-manager.io/v1
    kind: Certificate
    metadata:
      name: traefik-cert
      namespace: ${kubernetes_namespace_v1.traefik.metadata[0].name}
    spec:
      secretName: traefik-certs
      issuerRef:
        name: letsencrypt-cloudflare
        kind: ClusterIssuer
      dnsNames:
        - traefik.${var.domain_name}
  YAML
}
