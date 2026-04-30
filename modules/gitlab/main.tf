# --- SECRETS ---
# Agora todos usam var.namespace vindo do root

resource "kubernetes_secret_v1" "gitlab_minio_secret" {
  metadata {
    name      = "gitlab-minio-secret"
    namespace = var.namespace
  }

  type = "Opaque"

  data = {
    "connection" = <<-EOT
provider: AWS
region: us-east-1
aws_access_key_id: ${var.minio_access_key}
aws_secret_access_key: ${var.minio_secret_key}
endpoint: http://minio.minio.svc.cluster.local:9000
path_style: true
EOT
  }
}

resource "kubernetes_secret_v1" "gitlab_root_secret" {
  metadata {
    name      = "gitlab-root-secret"
    namespace = var.namespace
  }

  type = "Opaque"

  data = {
    "password" = var.root_password != null ? var.root_password : "changeme123"
  }
}

resource "kubernetes_secret_v1" "gitlab_postgres_secret" {
  metadata {
    name      = "gitlab-postgres-secret"
    namespace = var.namespace
  }

  type = "Opaque"

  data = {
    "password" = "postgres" # Certifique-se que essa é a senha do seu módulo Postgres
  }
}

# --- HELM RELEASE GITLAB ---

resource "helm_release" "gitlab" {
  name      = "gitlab"
  chart     = "${path.module}/gitlab"
  version   = var.chart_version
  namespace = var.namespace

  timeout         = 1200 # Aumentado para 20min (GitLab no k3d é pesado)
  wait            = false
  wait_for_jobs   = false
  cleanup_on_fail = true
  atomic          = false
  max_history     = 3

  depends_on = [
    kubernetes_secret_v1.gitlab_postgres_secret,
    kubernetes_secret_v1.gitlab_minio_secret,
    kubernetes_secret_v1.gitlab_root_secret
  ]

  values = [
    <<-YAML
    global:
      edition: ce
      ingress:
        enabled: true
        class: traefik
        provider: ""
        configureCertmanager: false
        annotations:
          kubernetes.io/ingress.class: "traefik"
          traefik.ingress.kubernetes.io/router.middlewares: "${var.namespace}-traefik-force-https-header@kubernetescrd"
      hosts:
        domain: ${var.domain_name}
        gitlab:
          name: ${var.domain_name}
        https: true
        registry:
          name: registry.${var.domain_name}
      image:
        tag: ${var.gitlab_version}

      minio:
        enabled: false

      initialRootPassword:
        secret: gitlab-root-secret
        key: password

      psql:
        host: postgres.postgres.svc.cluster.local
        port: 5433
        username: postgres
        database: gitlabhq_production
        password:
          secret: gitlab-postgres-secret
          key: password

      appConfig:
        trusted_proxies: ${jsonencode(var.trusted_proxies)}
        object_store:
          enabled: true
          proxy_download: true
          connection:
            secret: gitlab-minio-secret
            key: connection
        lfs: { enabled: true, bucket: gitlab-lfs }
        artifacts: { enabled: true, bucket: gitlab-artifacts }
        packages: { enabled: true, bucket: gitlab-packages }
        uploads: { enabled: true, bucket: gitlab-uploads }
        registry: { enabled: true, bucket: gitlab-registry }

    certmanager: { install: false }
    nginx-ingress: { enabled: false }
    prometheus: { install: false }
    gitlab-exporter: { enabled: false }
    postgresql: { install: false }
    gitlab-runner: { install: false }

    redis:
      install: true
      resources:
        requests:
          cpu: 100m
          memory: 256Mi

    gitlab:
      webservice:
        extraEnv:
          GITLAB_HTTPS: "true"
          RAILS_TRUSTED_PROXIES: "${join(",", var.trusted_proxies)}"
        minReplicas: 1
        maxReplicas: 1
        workerTimeout: 1800
        resources:
          requests:
            cpu: 800m
            memory: 2Gi
        livenessProbe:
          initialDelaySeconds: 300
        readinessProbe:
          initialDelaySeconds: 150

      sidekiq:
        resources:
          requests:
            cpu: 300m
            memory: 1Gi

      gitaly:
        securityContext:
          runAsUser: 1000
          fsGroup: 1000
        persistence:
          enabled: true
          storageClass: "local-path"
          size: 100Gi
    YAML
  ]
}

# --- GITLAB RUNNER ---

resource "helm_release" "gitlab_runner" {
  depends_on = [helm_release.gitlab]

  name       = "gitlab-runner"
  repository = "https://charts.gitlab.io/"
  chart      = "gitlab-runner"
  namespace  = var.namespace
  version    = "0.70.0"

  values = [
    <<-YAML
    gitlabUrl: http://gitlab-webservice-default.${var.namespace}.svc.cluster.local:8181
    runnerToken: ${var.runner_authentication_token}
    runners:
      privileged: true
      executor: kubernetes
    YAML
  ]
}

# --- OUTPUTS ---

output "gitlab_url" {
  value = "https://${var.domain_name}"
}