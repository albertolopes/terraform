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
  timeout          = 1800
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
        https: false
        gitlab:
          name: ${var.domain_name}
      ingress:
        enabled: true
        class: traefik
        annotations:
          kubernetes.io/ingress.provider: traefik
          traefik.ingress.kubernetes.io/router.tls: "false"
          ingress.kubernetes.io/ssl-redirect: "false"
        configureCertmanager: false
        tls:
          enabled: false
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
      runners:
        config: |
          [[runners]]
            [runners.kubernetes]
              namespace = "${var.namespace}"
              image = "alpine:latest"
              privileged = true
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
      enabled: false

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
        env:
          - name: PUMA_WORKERS
            value: "2"
          - name: GITLAB_RAILS_RACK_TIMEOUT
            value: "600"
        resources:
          requests:
            cpu: 1000m
            memory: 2Gi
          limits:
            cpu: 4000m
            memory: 6Gi
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
        workerProcesses: 2
        persistence:
          enabled: false

      sidekiq:
        enabled: true
        minReplicas: 1
        maxReplicas: 2
        resources:
          requests:
            cpu: 1000m
            memory: 2Gi
          limits:
            cpu: 4000m
            memory: 4Gi
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
            cpu: 1m
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

    gitlab-runner:
      install: true
      runners:
        privileged: true
        executor: kubernetes
        tags: "kubernetes,gitlab,runner"
        request_concurrency: 4
        build_image: alpine:latest
        runUntagged: true
        protected: true
        output_limit: 4096
        kubernetes:
          namespace: "${var.namespace}"
          image: alpine:latest
          privileged: true
          allow_privilege_escalation: true
          cpu_limit: "2"
          memory_limit: "2Gi"
          cpu_request: "500m"
          memory_request: "512Mi"
          helper_image: "gitlab/gitlab-runner-helper:x86_64-latest"
          service_account: gitlab-runner
          pod_labels: "app=gitlab-runner"
          poll_timeout: 360
          poll_interval: 3
      resources:
        requests:
          cpu: 100m
          memory: 256Mi
        limits:
          cpu: 1000m
          memory: 1Gi
    YAML
  ]

  depends_on = [
    kubernetes_namespace_v1.gitlab,
    kubernetes_secret_v1.gitlab_root_secret,
    kubernetes_secret_v1.gitlab_postgres_secret,
    kubernetes_secret_v1.gitlab_redis_secret,
    kubernetes_secret_v1.gitlab_minio_secret,
  ]
}

output "gitlab_url" {
  value = "http://${var.domain_name}"
}

output "gitlab_status_command" {
  value = "kubectl get pods -n ${var.namespace} -w"
}

output "gitlab_logs_command" {
  value = "kubectl logs -n ${var.namespace} -l app=webservice --tail=100"
}