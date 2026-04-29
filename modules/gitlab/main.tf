resource "kubernetes_namespace_v1" "gitlab" {
  metadata {
    name = var.namespace
  }
}

# --- SECRETS ---
resource "kubernetes_secret_v1" "gitlab_minio_secret" {
  metadata {
    name      = "gitlab-minio-secret"
    namespace = kubernetes_namespace_v1.gitlab.metadata[0].name
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

resource "kubernetes_secret_v1" "gitlab_postgres_secret" {
  metadata {
    name      = "gitlab-postgres-secret"
    namespace = kubernetes_namespace_v1.gitlab.metadata[0].name
  }
  type = "Opaque"
  data = {
    "password" = "postgres"
  }
}

resource "kubernetes_secret_v1" "gitlab_root_secret" {
  metadata {
    name      = "gitlab-root-secret"
    namespace = kubernetes_namespace_v1.gitlab.metadata[0].name
  }
  type = "Opaque"
  data = {
    "password" = var.root_password != null ? var.root_password : "changeme123"
  }
}

# --- HELM RELEASE GITLAB ---
resource "helm_release" "gitlab" {
  name             = "gitlab"
  repository       = "https://charts.gitlab.io/"
  chart            = "gitlab"
  version          = var.chart_version
  namespace        = kubernetes_namespace_v1.gitlab.metadata[0].name
  timeout          = 3600
  wait             = true
  wait_for_jobs    = true
  cleanup_on_fail  = true

  depends_on = [
    kubernetes_secret_v1.gitlab_postgres_secret,
    kubernetes_secret_v1.gitlab_minio_secret,
    kubernetes_secret_v1.gitlab_root_secret
  ]

  values = [
    <<-YAML
    global:
      edition: ce
      hosts:
        domain: ${var.domain_name}
        https: true
      image:
        tag: ${var.gitlab_version}

      # VINCULA A SENHA ROOT AQUI
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

    certmanager-issuer: { email: "admin@${var.domain_name}" }
    certmanager: { install: false }
    nginx: { enabled: false }
    prometheus: { install: false }
    gitlab-exporter: { enabled: false }
    postgresql: { install: false }

    redis:
      install: true
      resources:
        requests:
          cpu: 200m
          memory: 512Mi

    gitlab:
      webservice:
        enabled: true
        minReplicas: 1
        maxReplicas: 1
        workerProcesses: 2
        resources:
          requests:
            cpu: 1200m
            memory: 3Gi
          limits:
            cpu: 3000m
            memory: 5Gi
        livenessProbe:
          initialDelaySeconds: 900
          periodSeconds: 30
        readinessProbe:
          initialDelaySeconds: 600
          periodSeconds: 10

      sidekiq:
        resources:
          requests:
            cpu: 500m
            memory: 1.5Gi
          limits:
            cpu: 1500m
            memory: 2.5Gi

      gitlab-shell:
        resources:
          requests:
            cpu: 100m
            memory: 128Mi

      kas:
        resources:
          requests:
            cpu: 100m
            memory: 128Mi

      toolbox:
        resources:
          requests:
            cpu: 200m
            memory: 512Mi

      migrations:
        resources:
          requests:
            cpu: 800m
            memory: 1.5Gi

    ingress:
      enabled: true
      class: traefik
      annotations:
        kubernetes.io/ingress.provider: traefik
        traefik.ingress.kubernetes.io/router.middlewares: traefik-force-https-header@kubernetescrd
      configureCertmanager: false
      tls:
        enabled: true
        secretName: nginx-certs # Certifique-se que este secret existe!
    YAML
  ]
}

# --- RUNNER ---
resource "helm_release" "gitlab_runner" {
  depends_on = [helm_release.gitlab]
  name       = "gitlab-runner"
  repository = "https://charts.gitlab.io/"
  chart      = "gitlab-runner"
  # Referência direta ao namespace do recurso anterior
  namespace  = kubernetes_namespace_v1.gitlab.metadata[0].name
  version    = "0.70.0"

  values = [
    <<-YAML
    # Melhorado para usar interpolação do Terraform no nome do serviço
    gitlabUrl: http://gitlab-webservice-default.${kubernetes_namespace_v1.gitlab.metadata[0].name}.svc.cluster.local:8181
    runnerToken: ${var.runner_authentication_token}
    checkInterval: 30
    rbac: { create: true }
    runners:
      privileged: true
      executor: kubernetes
      resources:
        requests:
          cpu: 200m
          memory: 512Mi
        limits:
          cpu: 2000m
          memory: 4Gi
    YAML
  ]
}