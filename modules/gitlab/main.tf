# modules/gitlab/main.tf

terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
    }
    helm = {
      source  = "hashicorp/helm"
    }
  }
}

resource "kubernetes_namespace_v1" "gitlab" {
  metadata {
    name = var.namespace
  }
}

# Usar kubernetes_manifest em vez de kubectl_manifest
resource "kubernetes_manifest" "gitlab_minio_secret" {
  manifest = {
    apiVersion = "v1"
    kind = "Secret"
    metadata = {
      name = "gitlab-minio-secret"
      namespace = var.namespace
    }
    type = "Opaque"
    stringData = {
      connection = <<-EOT
        [default]
        host = minio.default.svc.cluster.local:9000
        access_key = ${var.minio_access_key}
        secret_key = ${var.minio_secret_key}
        use_ssl = false
      EOT
      accesskey = var.minio_access_key
      secretkey = var.minio_secret_key
    }
  }
}

resource "kubernetes_manifest" "gitlab_root_secret" {
  manifest = {
    apiVersion = "v1"
    kind = "Secret"
    metadata = {
      name = "gitlab-root-secret"
      namespace = var.namespace
    }
    type = "Opaque"
    stringData = {
      password = var.root_password != null ? var.root_password : "changeme123"
    }
  }
}

resource "kubernetes_manifest" "gitlab_postgres_secret" {
  manifest = {
    apiVersion = "v1"
    kind = "Secret"
    metadata = {
      name = "gitlab-postgres-secret"
      namespace = var.namespace
    }
    type = "Opaque"
    stringData = {
      password = "postgres"
    }
  }
}

resource "kubernetes_manifest" "gitlab_redis_secret" {
  manifest = {
    apiVersion = "v1"
    kind = "Secret"
    metadata = {
      name = "gitlab-redis-secret"
      namespace = var.namespace
    }
    type = "Opaque"
    stringData = {
      redis-password = "gitlab-redis-password"
    }
  }
}

resource "helm_release" "gitlab" {
  name             = "gitlab"
  repository       = "https://charts.gitlab.io/"
  chart            = "gitlab"
  version          = var.chart_version
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
          name: gitlab.${var.domain_name}
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

    minio:
      install: false
      enabled: false

    registry:
      enabled: false

    nginx-ingress:
      enabled: false

    postgresql:
      install: false

    redis:
      install: true
      auth:
        existingSecret: gitlab-redis-secret
        enabled: true
      master:
        resources:
          requests:
            memory: 256Mi
            cpu: 100m
          limits:
            memory: 512Mi
            cpu: 500m
        persistence:
          enabled: true
          size: 8Gi

    gitlab:
      webservice:
        enabled: true
        minReplicas: 1
        maxReplicas: 1
        hpa:
          enabled: false
        env:
          - name: PUMA_WORKERS
            value: "1"
          - name: GITLAB_RAILS_RACK_TIMEOUT
            value: "600"
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
        workerProcesses: 1
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
        maxReplicas: 1
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

      gitaly:
        enabled: true
        resources:
          requests:
            cpu: 200m
            memory: 512Mi
          limits:
            cpu: 1000m
            memory: 1Gi
        persistence:
          enabled: true
          size: 20Gi
        service:
          port: 8075

      gitlab-shell:
        enabled: true
        minReplicas: 1
        maxReplicas: 1
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 128Mi

      kas:
        enabled: true
        minReplicas: 1
        maxReplicas: 1
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 128Mi
        service:
          externalPort: 8150
          internalPort: 8153

      toolbox:
        enabled: true
        resources:
          requests:
            cpu: 200m
            memory: 512Mi
          limits:
            cpu: 800m
            memory: 1Gi
        backups:
          cron:
            enabled: false

      migrations:
        enabled: true
        resources:
          requests:
            cpu: 200m
            memory: 512Mi
          limits:
            cpu: 1000m
            memory: 1Gi

      praefect:
        enabled: false

      initialBuckets:
        - gitlab-lfs
        - gitlab-artifacts
        - gitlab-uploads
        - gitlab-packages

    nginx:
      enabled: false

    gitlab-exporter:
      enabled: false
    YAML
  ]

  depends_on = [
    kubernetes_namespace_v1.gitlab,
    kubernetes_manifest.gitlab_root_secret,
    kubernetes_manifest.gitlab_postgres_secret,
    kubernetes_manifest.gitlab_redis_secret,
    kubernetes_manifest.gitlab_minio_secret,
  ]
}

# Outputs
output "gitlab_url" {
  value = "http://gitlab.${var.domain_name}"
}

output "gitlab_status_command" {
  value = "kubectl get pods -n ${var.namespace}"
}

output "gitlab_logs_command" {
  value = "kubectl logs -n ${var.namespace} -l app=webservice --tail=100"
}