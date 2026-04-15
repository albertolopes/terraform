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
  namespace        = kubernetes_namespace_v1.gitlab.metadata[0].name
  timeout          = 600
  create_namespace = false
  wait             = true
  wait_for_jobs    = true

  values = [
    <<-YAML
    global:
      hosts:
        domain: ${var.domain_name}
        https: false
      ingress:
        enabled: true
        class: traefik
        createIngressClass: false
        tls:
          enabled: false
        configureCertmanager: false
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

    prometheus:
      install: false

    gitlab-runner:
      install: false

    minio:
      install: true
      mode: standalone
      auth:
        existingSecret: gitlab-minio-secret
      resources:
        requests:
          memory: 512Mi
          cpu: 100m
        limits:
          memory: 1Gi
          cpu: 500m

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

    gitlab:
      webservice:
        minReplicas: 1
        maxReplicas: 1
        resources:
          requests:
            cpu: 1000m
            memory: 1Gi
          limits:
            cpu: 2000m
            memory: 3Gi
        livenessProbe:
          initialDelaySeconds: 300
          periodSeconds: 30
          timeoutSeconds: 10
          failureThreshold: 5
        readinessProbe:
          initialDelaySeconds: 240
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 5

      sidekiq:
        minReplicas: 1
        maxReplicas: 1
        resources:
          requests:
            cpu: 200m
            memory: 2Gi
          limits:
            cpu: 2000m
            memory: 2Gi
        livenessProbe:
          initialDelaySeconds: 300
          periodSeconds: 30
          timeoutSeconds: 10
          failureThreshold: 5
        readinessProbe:
          initialDelaySeconds: 60
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 5

      gitaly:
        resources:
          requests:
            cpu: 100m
            memory: 256Mi
          limits:
            cpu: 500m
            memory: 512Mi

      gitlab-shell:
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
        minReplicas: 1
        maxReplicas: 1
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 128Mi

      toolbox:
        enabled: true
        resources:
          requests:
            cpu: 100m
            memory: 512Mi
          limits:
            cpu: 800m
            memory: 1G

      migrations:
        enabled: true
        resources:
          requests:
            cpu: 100m
            memory: 256Mi
          limits:
            cpu: 500m
            memory: 512Mi
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