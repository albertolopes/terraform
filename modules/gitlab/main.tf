# modules/gitlab/main.tf

resource "kubernetes_namespace_v1" "gitlab" {
  metadata {
    name = var.namespace
  }
}

# Usar kubernetes_secret_v1 em vez de kubernetes_manifest
resource "kubernetes_secret_v1" "gitlab_minio_secret" {
  metadata {
    name      = "gitlab-minio-secret"
    namespace = var.namespace
  }

  type = "Opaque"

  data = {
    "connection" = base64encode(<<-EOT
[default]
host = minio.minio.svc.cluster.local:9000
access_key = ${var.minio_access_key}
secret_key = ${var.minio_secret_key}
use_ssl = false
EOT
    )
    "accesskey" = base64encode(var.minio_access_key)
    "secretkey" = base64encode(var.minio_secret_key)
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
    "password" = base64encode("postgres")
  }
}

resource "helm_release" "gitlab" {
  name             = "gitlab"
  chart            = "${path.module}/charts/gitlab"  # Chart local
  namespace        = kubernetes_namespace_v1.gitlab.metadata[0].name
  timeout          = 1800
  create_namespace = false
  wait             = true
  wait_for_jobs    = true
  atomic           = true
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
        configureCertmanager: false
        tls:
          enabled: false
      initialRootPassword:
        secret: gitlab-root-secret
      psql:
        host: postgres.postgres.svc.cluster.local
        port: 5432
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
          secret: redis-password-secret
          key: redis-password
        install: false
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
        containerRegistry:
          enabled: false
        pseudonymizer:
          enabled: false
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

    gitlab-runner:
      install: false

    registry:
      enabled: false

    nginx-ingress:
      enabled: false

    postgresql:
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
        workerProcesses: 2
        persistence:
          enabled: false
        objectStorage:
          enabled: true
          config:
            secret: gitlab-minio-secret
            key: connection

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
            cpu: 500m
            memory: 256Mi
        service:
          externalPort: 8150
          internalPort: 8153

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

  depends_on = [
    kubernetes_namespace_v1.gitlab,
    kubernetes_secret_v1.gitlab_root_secret,
    kubernetes_secret_v1.gitlab_postgres_secret,
    kubernetes_secret_v1.gitlab_minio_secret,
  ]
}

# Outputs
output "gitlab_url" {
  value = "http://${var.domain_name}"
}

output "gitlab_status_command" {
  value = "kubectl get pods -n ${var.namespace} -w"
}

output "gitlab_logs_command" {
  value = "kubectl logs -n ${var.namespace} -l app=webservice --tail=100"
}