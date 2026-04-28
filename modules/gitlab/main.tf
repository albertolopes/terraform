resource "kubernetes_namespace_v1" "gitlab" {
  metadata {
    name = var.namespace
  }
}

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
    "password" = "postgres"
  }
}

resource "kubernetes_secret_v1" "gitlab_redis_secret" {
  metadata {
    name      = "gitlab-redis-secret"
    namespace = var.namespace
  }

  type = "Opaque"

  data = {
    "redis-password" = var.redis_password
  }
}

resource "helm_release" "gitlab" {
  name             = "gitlab"
  repository       = "https://charts.gitlab.io/"
  chart            = "gitlab"
  version          = "8.4.0"
  namespace        = kubernetes_namespace_v1.gitlab.metadata[0].name
  timeout          = 3600
  create_namespace = false
  wait             = true
  wait_for_jobs    = true
  atomic           = false
  cleanup_on_fail  = true
  max_history      = 3

  values = [
    <<-YAML
    global:
      edition: ce
      hosts:
        domain: ${var.domain_name}
        https: true
      image:
        tag: ${var.gitlab_version}
      appConfig:
        lfs:
          enabled: true
          bucket: gitlab-lfs
        artifacts:
          enabled: true
          bucket: gitlab-artifacts
        packages:
          enabled: true
          bucket: gitlab-packages
        uploads:
          enabled: true
          bucket: gitlab-uploads
        registry:
          enabled: true
          bucket: gitlab-registry
        object_store:
          enabled: true
          proxy_download: true
          connection:
            secret: gitlab-minio-secret
            key: connection

    certmanager:
      install: false

    nginx:
      enabled: false

    prometheus:
      install: false

    gitlab-exporter:
      enabled: false

    gitlab:
      webservice:
        enabled: true
        minReplicas: 1
        maxReplicas: 1
        hpa:
          enabled: false
        env:
          - name: PUMA_WORKERS
            value: "2"
          - name: GITLAB_RAILS_RACK_TIMEOUT
            value: "600"
        resources:
          requests:
            cpu: 2000m
            memory: 2Gi
          limits:
            cpu: 6000m
            memory: 7.5Gi
        livenessProbe:
          initialDelaySeconds: 900
          periodSeconds: 30
          timeoutSeconds: 10
          failureThreshold: 15
        readinessProbe:
          initialDelaySeconds: 600
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 15

      gitlab-shell:
        enabled: true
        minReplicas: 1
        maxReplicas: 2
        resources:
          requests:
            cpu: 200m
            memory: 256Mi
          limits:
            cpu: 1000m
            memory: 512Mi

      kas:
        enabled: true
        minReplicas: 1
        maxReplicas: 2
        resources:
          requests:
            cpu: 200m
            memory: 256Mi
          limits:
            cpu: 1000m
            memory: 1Gi
        service:
          externalPort: 8150
          internalPort: 8156

      toolbox:
        enabled: true
        resources:
          requests:
            cpu: 500m
            memory: 1Gi
          limits:
            cpu: 3000m
            memory: 3Gi
        backups:
          cron:
            enabled: false

      migrations:
        enabled: true
        resources:
          requests:
            cpu: 1000m
            memory: 2Gi
          limits:
            cpu: 3000m
            memory: 4Gi

    postgresql:
      install: false

    psql:
      host: postgres.postgres.svc.cluster.local
      port: 5433
      username: postgres
      password:
        secret: gitlab-postgres-secret
        key: password
      database: gitlabhq_production

    redis:
      install: false
      host: redis.redis.svc.cluster.local
      port: 6379
      password:
        secret: gitlab-redis-secret
        key: redis-password

    ingress:
      enabled: true
      class: traefik
      annotations:
        kubernetes.io/ingress.provider: traefik
        traefik.ingress.kubernetes.io/router.middlewares: traefik-force-https-header@kubernetescrd
      configureCertmanager: false
      tls:
        enabled: true
        secretName: nginx-certs
    YAML
  ]
}

# Data source para pegar o IP do serviço do GitLab
data "kubernetes_service" "gitlab_webservice" {
  depends_on = [helm_release.gitlab]
  metadata {
    name      = "gitlab-webservice-default"
    namespace = var.namespace
  }
}

# Data source para pegar o IP do serviço do Traefik
data "kubernetes_service" "traefik" {
  metadata {
    name      = "traefik"
    namespace = "traefik"
  }
}

# Instalar GitLab Runner
resource "helm_release" "gitlab_runner" {
  depends_on = [helm_release.gitlab, data.kubernetes_service.gitlab_webservice, data.kubernetes_service.traefik]

  name       = "gitlab-runner"
  repository = "https://charts.gitlab.io/"
  chart      = "gitlab-runner"
  namespace  = var.namespace
  version    = "0.70.0"
  timeout    = 1800
  create_namespace = false
  wait       = true
  atomic     = false

  values = [
    <<-YAML
    gitlabUrl: http://gitlab-webservice-default.${var.namespace}.svc.cluster.local:8181
    runnerToken: ${var.runner_authentication_token}
    checkInterval: 30
    rbac:
      create: true

    hostAliases:
      - ip: "${data.kubernetes_service.traefik.spec[0].cluster_ip}"
        hostnames:
          - "${var.domain_name}"
          - "gitlab.${var.domain_name}"
          - "registry.${var.domain_name}"

    runners:
      privileged: true
      executor: kubernetes
      tags: "kubernetes"
      runUntagged: true
      secretName: gitlab-runner-secret
      env:
        CI_SERVER_URL: http://gitlab-webservice-default.${var.namespace}.svc.cluster.local:8181
        CI_SERVER_HOST: gitlab-webservice-default.${var.namespace}.svc.cluster.local
        CI_SERVER_PORT: "8181"
        job_timeout: 3600
        output_limit: 40960
      kubernetes:
        cpu_limit: "2"
        memory_limit: "8Gi"
        cpu_request: "2"
        memory_request: "4Gi"
        helper_cpu_limit: "2"
        helper_memory_limit: "4Gi"
        helper_cpu_request: "1"
        helper_memory_request: "2Gi"
        poll_timeout: 600
        poll_interval: 10
      resources:
        requests:
          cpu: 1000m
          memory: 2Gi
        limits:
          cpu: 4
          memory: 8Gi
    YAML
  ]
}

output "gitlab_url" {
  value = "https://${var.domain_name}"
}

output "gitlab_status_command" {
  value = "kubectl get pods -n ${var.namespace} -w"
}

output "gitlab_logs_command" {
  value = "kubectl logs -n ${var.namespace} -l app=webservice --tail=100"
}