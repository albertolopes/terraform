# --- SECRETS ---

resource "kubernetes_secret_v1" "gitlab_minio_secret" {
  metadata {
    name      = "gitlab-minio-secret"
    namespace = var.namespace
  }
  type = "Opaque"
  data = {
    "connection" = base64encode(<<-EOT
provider: AWS
region: us-east-1
aws_access_key_id: ${var.minio_access_key}
aws_secret_access_key: ${var.minio_secret_key}
endpoint: http://minio.minio.svc.cluster.local:9000
path_style: true
EOT
    )
  }
}

resource "kubernetes_secret_v1" "gitlab_root_secret" {
  metadata {
    name      = "gitlab-root-secret"
    namespace = var.namespace
  }
  type = "Opaque"
  data = {
    "password" = base64encode(var.root_password != null ? var.root_password : "changeme123")
  }
}

resource "kubernetes_secret_v1" "gitlab_postgres_secret" {
  metadata {
    name      = "gitlab-postgres-secret"
    namespace = var.namespace
  }
  type = "Opaque"
  data = {
    "password" = base64encode(var.postgres_password)
  }
}

resource "kubernetes_secret_v1" "gitlab_redis_password" {
  metadata {
    name      = "gitlab-redis-password"
    namespace = var.namespace
  }
  type = "Opaque"
  data = {
    "password" = base64encode(var.redis_password)
  }
}

# --- HELM RELEASE GITLAB ---

resource "helm_release" "gitlab" {
  name      = "gitlab"
  chart     = "${path.module}/gitlab"
  version   = var.chart_version
  namespace = var.namespace

  timeout         = 1800
  wait            = false
  wait_for_jobs   = false
  cleanup_on_fail = true
  atomic          = false
  max_history     = 3

  depends_on = [
    kubernetes_secret_v1.gitlab_postgres_secret,
    kubernetes_secret_v1.gitlab_minio_secret,
    kubernetes_secret_v1.gitlab_root_secret,
    kubernetes_secret_v1.gitlab_redis_password
  ]

  values = [
    <<-YAML
    global:
      edition: ce
      ingress:
        enabled: true
        class: traefik
        configureCertmanager: false
        annotations:
          kubernetes.io/ingress.class: "traefik"
          traefik.ingress.kubernetes.io/router.middlewares: "${var.namespace}-traefik-force-https-header@kubernetescrd"
      hosts:
        domain: ${var.domain_name}
        gitlab:
          name: ${var.domain_name}
        https: true

      redis:
        host: redis.redis.svc.cluster.local
        port: 6379
        password:
          secret: gitlab-redis-password
          key: password

      psql:
        host: postgres.postgres.svc.cluster.local
        port: 5433
        username: postgres
        database: gitlabhq_production
        password:
          secret: gitlab-postgres-secret
          key: password

    certmanager: { install: false }
    certmanager-issuer: { install: false }
    redis: { install: false }
    postgresql: { install: false }
    nginx-ingress: { enabled: false }
    prometheus: { install: false }
    gitlab-runner: { install: false }

    gitlab:
      webservice:
        minReplicas: 1
        maxReplicas: 1
        resources:
          requests:
            cpu: 800m
            memory: 2Gi
          limits:
            cpu: 1500m
            memory: 4Gi

      sidekiq:
        minReplicas: 1
        maxReplicas: 1
        resources:
          requests:
            cpu: 300m
            memory: 1Gi
          limits:
            cpu: 800m
            memory: 2Gi

      toolbox:
        resources:
          requests:
            cpu: 300m
            memory: 1Gi

      gitaly:
        resources:
          requests:
            cpu: 400m
            memory: 1Gi
        persistence:
          enabled: true
          storageClass: "local-path"
          size: 50Gi

      gitlab-shell:
        minReplicas: 1
        maxReplicas: 1

    gitlab-kas: { minReplicas: 1, maxReplicas: 1 }
    registry: { hpa: { minReplicas: 1, maxReplicas: 1 } }
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