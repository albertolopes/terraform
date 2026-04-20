# modules/gitlab/variables.tf
variable "gitlab_version" {
  description = "GitLab version to install"
  type        = string
  default     = "17.9.0"
}

variable "chart_version" {
  description = "GitLab Helm chart version"
  type        = string
  default     = "8.4.0"
}

# modules/gitlab/main.tf

resource "kubernetes_namespace_v1" "gitlab" {
  metadata {
    name = var.namespace
  }
}

resource "kubectl_manifest" "gitlab_root_secret" {
  yaml_body = <<-YAML
    apiVersion: v1
    kind: Secret
    metadata:
      name: gitlab-root-secret
      namespace: ${var.namespace}
    type: Opaque
    stringData:
      password: ${var.root_password != null ? var.root_password : "changeme123"}
  YAML
}

resource "kubectl_manifest" "gitlab_postgres_secret" {
  yaml_body = <<-YAML
    apiVersion: v1
    kind: Secret
    metadata:
      name: gitlab-postgres-secret
      namespace: ${var.namespace}
    type: Opaque
    stringData:
      password: postgres
  YAML
}

resource "kubectl_manifest" "gitlab_redis_secret" {
  yaml_body = <<-YAML
    apiVersion: v1
    kind: Secret
    metadata:
      name: gitlab-redis-secret
      namespace: ${var.namespace}
    type: Opaque
    stringData:
      redis-password: gitlab-redis-password
  YAML
}

resource "kubectl_manifest" "gitlab_minio_secret" {
  yaml_body = <<-YAML
    apiVersion: v1
    kind: Secret
    metadata:
      name: gitlab-minio-secret
      namespace: ${var.namespace}
    type: Opaque
    stringData:
      accesskey: minioadmin
      secretkey: minioadmin123
  YAML
}

resource "helm_release" "gitlab" {
  name             = "gitlab"
  repository       = "https://charts.gitlab.io/"
  chart            = "gitlab"
  version          = var.chart_version
  namespace        = kubernetes_namespace_v1.gitlab.metadata[0].name
  timeout          = 1200
  create_namespace = false
  wait             = true
  wait_for_jobs    = true
  atomic           = true
  cleanup_on_fail  = true

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
        port: 5433
        username: postgres
        password:
          secret: gitlab-postgres-secret
          key: password
        database: gitlabhq_production
      image:
        tag: ${var.gitlab_version}
        pullPolicy: IfNotPresent
      appConfig:
        lfs:
          enabled: true
        artifacts:
          enabled: true
        packages:
          enabled: true
        containerRegistry:
          enabled: false
        pseudonymizer:
          enabled: false

    certmanager:
      install: false

    prometheus:
      install: false

    gitlab-runner:
      install: false

    minio:
      install: true
      mode: standalone
      auth:
        existingSecret: gitlab-minio-secret
      defaultBuckets:
        - gitlab-lfs
        - gitlab-artifacts
        - gitlab-uploads
        - gitlab-packages
      resources:
        requests:
          memory: 256Mi
          cpu: 100m
        limits:
          memory: 512Mi
          cpu: 500m
      persistence:
        enabled: true
        size: 10Gi

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
          size: 5Gi

    gitlab:
      webservice:
        enabled: true
        minReplicas: 1
        maxReplicas: 2
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
          failureThreshold: 10
          successThreshold: 1
        readinessProbe:
          initialDelaySeconds: 300
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 10
          successThreshold: 1
        workerProcesses: 1
        persistence:
          enabled: false

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
          failureThreshold: 10
        readinessProbe:
          initialDelaySeconds: 300
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 10

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
          size: 10Gi
        service:
          port: 8075
        auth:
          token: gitlab-gitaly-token

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

      redis:
        cache:
          enabled: true
          host: gitlab-redis-master.${var.namespace}.svc.cluster.local
          port: 6379
          password:
            secret: gitlab-redis-secret
            key: redis-password
        queues:
          enabled: true
          host: gitlab-redis-master.${var.namespace}.svc.cluster.local
          port: 6379
          password:
            secret: gitlab-redis-secret
            key: redis-password
        sharedState:
          enabled: true
          host: gitlab-redis-master.${var.namespace}.svc.cluster.local
          port: 6379
          password:
            secret: gitlab-redis-secret
            key: redis-password

      objectStorage:
        enabled: true
        config:
          secret: gitlab-minio-secret
          key:
            accesskey: accesskey
            secretkey: secretkey
        artifacts:
          bucket: gitlab-artifacts
        lfs:
          bucket: gitlab-lfs
        uploads:
          bucket: gitlab-uploads
        packages:
          bucket: gitlab-packages
        external:
          endpoint: http://gitlab-minio-svc.${var.namespace}.svc.cluster.local:9000

    nginx:
      enabled: false

    gitlab-exporter:
      enabled: true
      resources:
        requests:
          cpu: 50m
          memory: 128Mi
        limits:
          cpu: 200m
          memory: 256Mi
    YAML
  ]

  depends_on = [
    kubernetes_namespace_v1.gitlab,
    kubectl_manifest.gitlab_root_secret,
    kubectl_manifest.gitlab_postgres_secret,
    kubectl_manifest.gitlab_redis_secret,
    kubectl_manifest.gitlab_minio_secret
  ]
}

# Outputs
output "gitlab_access_info" {
  value = <<-EOT
    GitLab has been deployed successfully!

    URL: http://gitlab.${var.domain_name}
    Username: root
    Password: ${var.root_password != null ? var.root_password : "changeme123"}

    Monitor deployment:
    kubectl get pods -n ${var.namespace}
    kubectl logs -n ${var.namespace} -l app=webservice --tail=100
  EOT
  sensitive = true
}

output "gitlab_url" {
  value = "http://gitlab.${var.domain_name}"
}

output "gitlab_status_command" {
  value = "kubectl get pods -n ${var.namespace}"
}