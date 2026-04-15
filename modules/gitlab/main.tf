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

    gitlab:
      webservice:
        minReplicas: 1
        maxReplicas: 1
        resources:
          requests:
            cpu: 300m
            memory: 1Gi
          limits:
            cpu: 1500m
            memory: 2Gi
        livenessProbe:
          initialDelaySeconds: 300
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        readinessProbe:
          initialDelaySeconds: 240
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 2

      sidekiq:
        minReplicas: 1
        maxReplicas: 1
        resources:
          requests:
            cpu: 50m
            memory: 128Mi
          limits:
            cpu: 200m
            memory: 256Mi

      gitaly:
        resources:
          requests:
            cpu: 50m
            memory: 128Mi
          limits:
            cpu: 200m
            memory: 256Mi

      gitlab-shell:
        minReplicas: 1
        maxReplicas: 1
        resources:
          requests:
            cpu: 25m
            memory: 32Mi

      kas:
        minReplicas: 1
        maxReplicas: 1
        resources:
          requests:
            cpu: 25m
            memory: 32Mi

      toolbox:
        enabled: true

      migrations:
        enabled: true
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