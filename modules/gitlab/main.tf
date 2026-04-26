# modules/gitlab/main.tf

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
endpoint: http://minio.default.svc.cluster.local:9000
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
  chart            = "${path.module}/charts/gitlab"
  namespace        = kubernetes_namespace_v1.gitlab.metadata[0].name
  timeout          = 3600
  create_namespace = false
  wait             = true
  wait_for_jobs    = true
  atomic           = false
  cleanup_on_fail  = true
  max_history      = 3

  lifecycle {
    ignore_changes = [values]
  }

  values = [
    <<-YAML
    global:
      edition: ce
      hosts:
        domain: ${var.domain_name}
        https: true
        gitlab:
          name: ${var.domain_name}
        registry:
          name: registry.${var.domain_name}
      ingress:
        enabled: true
        class: traefik
        annotations:
          kubernetes.io/ingress.provider: traefik
        configureCertmanager: false
        tls:
          enabled: true
          secretName: nginx-certs
      initialRootPassword:
        secret: gitlab-root-secret
      psql:
        host: postgres.postgres.svc.cluster.local
        port: 5433
        username: postgres
        password:
          secret: gitlab-postgres-secret
          key: password
        database: gitlabhq_production
      image:
        tag: ${var.gitlab_version}
        pullPolicy: IfNotPresent
      minio:
        enabled: false
      gitaly:
        enabled: true
      redis:
        host: redis.redis.svc.cluster.local
        port: 6379
        password:
          secret: gitlab-redis-secret
          key: redis-password
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

    prometheus:
      install: false

    registry:
      enabled: true
      ingress:
        enabled: true
        class: traefik
        annotations:
          kubernetes.io/ingress.provider: traefik

    nginx-ingress:
      enabled: false

    postgresql:
      install: false

    redis:
      install: false

    gitlab:
      webservice:
        enabled: true
        minReplicas: 1
        maxReplicas: 2
        hpa:
          enabled: false
        resources:
          requests:
            cpu: 500m
            memory: 1.5Gi
          limits:
            cpu: 3000m
            memory: 4Gi
        livenessProbe:
          initialDelaySeconds: 600
        readinessProbe:
          initialDelaySeconds: 300
        workerProcesses: 2
        persistence:
          enabled: false

      sidekiq:
        enabled: true
        minReplicas: 1
        maxReplicas: 2
        resources:
          requests:
            cpu: 500m
            memory: 1Gi
          limits:
            cpu: 2000m
            memory: 2Gi
        livenessProbe:
          initialDelaySeconds: 600
          periodSeconds: 30
          timeoutSeconds: 10
          failureThreshold: 15
        readinessProbe:
          initialDelaySeconds: 300
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 15

      gitlab-shell:
        enabled: true
        minReplicas: 1
        maxReplicas: 2
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 256Mi

      kas:
        enabled: true
        minReplicas: 1
        maxReplicas: 2
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 500Mi
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
            cpu: 2000m
            memory: 2Gi
        backups:
          cron:
            enabled: false

      migrations:
        enabled: true
        resources:
          requests:
            cpu: 500m
            memory: 1Gi
          limits:
            cpu: 2000m
            memory: 2Gi

      praefect:
        enabled: false

    nginx:
      enabled: false

    gitlab-exporter:
      enabled: false
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

# Instalar GitLab Runner separadamente via Helm
resource "helm_release" "gitlab_runner" {
  depends_on = [helm_release.gitlab, data.kubernetes_service.gitlab_webservice]

  name             = "gitlab-runner"
  repository       = "https://charts.gitlab.io/"
  chart            = "gitlab-runner"
  namespace        = var.namespace
  version          = "0.70.0"
  timeout          = 1800
  create_namespace = false
  wait             = true
  atomic           = false

  values = [
    <<-YAML
    gitlabUrl: http://gitlab-webservice-default.${var.namespace}.svc.cluster.local:8181
    runnerToken: ${var.runner_authentication_token}
    checkInterval: 30
    rbac:
      create: true
    runners:
      privileged: true
      executor: kubernetes
      tags: "kubernetes"
      runUntagged: true
      secretName: gitlab-runner-secret
      env:
        CI_SERVER_URL: http://gitlab-webservice-default.${var.namespace}.svc.cluster.local:8080
        CI_SERVER_HOST: gitlab-webservice-default.${var.namespace}.svc.cluster.local
        CI_SERVER_PORT: "8080"
      job_timeout: 3600
      output_limit: 40960
      kubernetes:
        cpu_limit: "4"
        memory_limit: "8Gi"
        cpu_request: "2"
        memory_request: "4Gi"
        helper_cpu_limit: "1"
        helper_memory_limit: "2Gi"
        helper_cpu_request: "500m"
        helper_memory_request: "1Gi"
        poll_timeout: 600
        poll_interval: 10
        host_aliases:
          - ip: "${data.kubernetes_service.gitlab_webservice.spec[0].cluster_ip}"
            hostnames:
              - "${var.domain_name}"
              - "gitlab.${var.domain_name}"
              - "registry.${var.domain_name}"
    resources:
      requests:
        cpu: 500m
        memory: 1Gi
      limits:
        cpu: 2
        memory: 4Gi
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