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

# --- HELM RELEASE GITLAB ---

resource "helm_release" "gitlab" {
  name            = "gitlab"
  chart           = "${path.module}/gitlab"
  version         = var.chart_version
  namespace       = kubernetes_namespace_v1.gitlab.metadata[0].name

  timeout         = 600
  wait            = false
  wait_for_jobs   = false
  cleanup_on_fail = true
  atomic          = false
  max_history     = 3

  depends_on = [
    kubernetes_secret_v1.gitlab_postgres_secret,
    kubernetes_secret_v1.gitlab_minio_secret,
    kubernetes_secret_v1.gitlab_root_secret
  ]

  values = [
    <<-YAML
    global:
      edition: ce
      ingress:
        enabled: true
        class: traefik
        # AJUSTE: Anula o provider para o Helm não assumir Nginx
        provider: ""
        configureCertmanager: false
      hosts:
        domain: ${var.domain_name}
        gitlab:
          name: ${var.domain_name}
        https: true
        registry:
          name: registry.${var.domain_name}
      image:
        tag: ${var.gitlab_version}

      minio:
        enabled: false

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
        trusted_proxies: ${jsonencode(var.trusted_proxies)}
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

    certmanager: { install: false }
    certmanager-issuer:
      install: false
      email: "admin@${var.domain_name}"

    nginx-ingress: { enabled: false }
    prometheus: { install: false }
    gitlab-exporter: { enabled: false }
    postgresql: { install: false }
    gitlab-runner: { install: false }

    redis:
      install: true
      image:
        registry: public.ecr.aws
        repository: bitnami/redis
        tag: 7.2.4-debian-12-r10
      metrics:
        enabled: false
      resources:
        requests:
          cpu: 100m
          memory: 256Mi

    gitlab:
      webservice:
        # --- TIRO DE MISERICÓRDIA NO ERRO 422 ---
        extraEnv:
          GITLAB_HTTPS: "true"
          RAILS_TRUSTED_PROXIES: "${join(",", var.trusted_proxies)}"
        # ----------------------------------------
        minReplicas: 1
        maxReplicas: 1
        workerProcesses: 2
        workerTimeout: 1800
        resources:
          requests:
            cpu: 800m
            memory: 2Gi
          limits:
            cpu: 2500m
            memory: 5Gi
        livenessProbe:
          initialDelaySeconds: 300
        readinessProbe:
          initialDelaySeconds: 150

      sidekiq:
        minReplicas: 1
        maxReplicas: 1
        resources:
          requests:
            cpu: 300m
            memory: 1Gi

      gitlab-shell:
        minReplicas: 1
        maxReplicas: 1
        resources:
          requests:
            cpu: 50m
            memory: 64Mi

      kas:
        minReplicas: 1
        maxReplicas: 1
        resources:
          requests:
            cpu: 50m
            memory: 64Mi

    registry:
      hpa:
        minReplicas: 1
        maxReplicas: 1

    ingress:
      enabled: true
      class: traefik
      annotations:
        kubernetes.io/ingress.class: traefik
        # AJUSTE: Força o provider a ficar vazio para limpar as anotações de Nginx
        kubernetes.io/ingress.provider: ""
        # CORREÇÃO 422: Referencia o middleware corretamente
        traefik.ingress.kubernetes.io/router.middlewares: gitlab-traefik-force-https-header@kubernetescrd
      configureCertmanager: false
      tls:
        enabled: true
        secretName: nginx-certs
    YAML
  ]
}

# --- GITLAB RUNNER ---

resource "helm_release" "gitlab_runner" {
  depends_on = [helm_release.gitlab]

  name       = "gitlab-runner"
  repository = "https://charts.gitlab.io/"
  chart      = "gitlab-runner"
  namespace  = kubernetes_namespace_v1.gitlab.metadata[0].name
  version    = "0.70.0"

  wait       = false

  values = [
    <<-YAML
    gitlabUrl: http://gitlab-webservice-default.${kubernetes_namespace_v1.gitlab.metadata[0].name}.svc.cluster.local:8181
    runnerToken: ${var.runner_authentication_token}
    checkInterval: 30
    rbac: { create: true }
    replicas: 1
    runners:
      privileged: true
      executor: kubernetes
      resources:
        requests:
          cpu: 100m
          memory: 256Mi
    YAML
  ]
}

# --- DATA & OUTPUTS ---

data "kubernetes_service" "gitlab_webservice" {
  depends_on = [helm_release.gitlab]
  metadata {
    name      = "gitlab-webservice-default"
    namespace = kubernetes_namespace_v1.gitlab.metadata[0].name
  }
}

output "gitlab_url" {
  value = "https://${var.domain_name}"
}

output "gitlab_status_command" {
  value = "kubectl get pods -n ${var.namespace} -w"
}
