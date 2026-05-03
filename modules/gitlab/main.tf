# --- SECRETS ---

resource "kubernetes_secret_v1" "gitlab_minio_secret" {
  metadata {
    name      = "gitlab-minio-secret"
    namespace = var.namespace
  }
  type = "Opaque"
  data = {
    "connection" = base64encode(<<-EOT
provider: AWS
region: us-east-1
aws_access_key_id: ${var.minio_access_key}
aws_secret_access_key: ${var.minio_secret_key}
endpoint: http://minio.minio.svc.cluster.local:9000
path_style: true
EOT
    )
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

resource "kubernetes_secret_v1" "gitlab_external_postgres_password" {
  metadata {
    name      = "gitlab-external-postgres-password"
    namespace = var.namespace
  }
  type = "Opaque"
  data = {
    # Corrigido: Removido base64encode para evitar codificação dupla,
    # já que a variável já contém o dado em base64.
    password = var.postgres_password_secret_data
  }
}

resource "kubernetes_secret_v1" "gitlab_redis_password" {
  metadata {
    name      = "gitlab-redis-password"
    namespace = var.namespace
  }
  type = "Opaque"
  data = {
    "password" = base64encode(var.redis_password)
  }
}

# --- HELM RELEASE GITLAB ---

resource "helm_release" "gitlab" {
  name       = "gitlab"
  chart      = "gitlab"
  repository = "https://charts.gitlab.io/"
  version    = "9.0.0"
  namespace  = var.namespace

  timeout         = 1800
  wait            = true
  wait_for_jobs   = false
  cleanup_on_fail = true
  max_history     = 3

  depends_on = [
    kubernetes_secret_v1.gitlab_external_postgres_password,
    kubernetes_secret_v1.gitlab_root_secret,
    kubernetes_secret_v1.gitlab_redis_password,
    kubernetes_secret_v1.gitlab_minio_secret
  ]

  values = [
    <<-YAML
    global:
      edition: ce
      ingress:
        enabled: true
        class: traefik
        configureCertmanager: false
        annotations:
          kubernetes.io/ingress.class: "traefik"
          traefik.ingress.kubernetes.io/router.middlewares: "${var.namespace}-traefik-force-https-header@kubernetescrd"
      hosts:
        domain: ${var.domain_name}
        gitlab:
          name: gitlab.${var.domain_name}
        https: true

      redis:
        host: redis.redis.svc.cluster.local
        port: 6379
        password:
          secret: gitlab-redis-password
          key: password

      psql:
        host: postgres.postgres.svc.cluster.local
        port: 5433
        username: postgres
        database: gitlabhq_production
        password:
          secret: gitlab-external-postgres-password
          key: password

    certmanager: { install: false }
    redis: { install: false }
    postgresql: { install: false }
    nginx-ingress: { enabled: false }
    prometheus: { install: false }
    gitlab-runner: { install: false }

    gitlab:
      webservice:
        minReplicas: 1
        maxReplicas: 1
        resources:
          requests:
            cpu: 800m
            memory: 2Gi
          limits:
            cpu: 1500m
            memory: 4Gi

      sidekiq:
        minReplicas: 1
        maxReplicas: 1
        resources:
          requests:
            cpu: 300m
            memory: 1Gi
          limits:
            cpu: 800m
            memory: 2Gi

      toolbox:
        resources:
          requests:
            cpu: 300m
            memory: 1Gi
        backups:
          objectStorage:
            config:
              secret: gitlab-minio-secret
              key: connection

      gitaly:
        resources:
          requests:
            cpu: 400m
            memory: 1Gi
        persistence:
          enabled: true
          storageClass: "local-path"
          size: 50Gi

      gitlab-shell:
        minReplicas: 1
        maxReplicas: 1

    gitlab-kas:
      minReplicas: 1
      maxReplicas: 1

    registry:
      hpa:
        minReplicas: 1
        maxReplicas: 1
    YAML
  ]
}

# --- AUTOMAÇÃO PÓS-INSTALL ---

resource "null_resource" "wait_for_gitlab_webservice" {
  depends_on = [helm_release.gitlab]
  provisioner "local-exec" {
    command = "kubectl wait --for=condition=available deployment/gitlab-webservice-default -n ${var.namespace} --timeout=900s"
    environment = {
      KUBECONFIG = "${path.cwd}/.k3d_kubeconfig"
    }
  }
}

data "external" "gitlab_runner_token" {
  depends_on = [null_resource.wait_for_gitlab_webservice]

  program = ["bash", "-c", <<-EOT
    export KUBECONFIG="${path.cwd}/.k3d_kubeconfig"
    set -euo pipefail

    kubectl wait --for=condition=ready pod -l app=toolbox,release=gitlab -n ${var.namespace} --timeout=600s > /dev/null 2>&1

    TOOLBOX_POD=$(kubectl get pod -l app=toolbox,release=gitlab -n ${var.namespace} -o jsonpath='{.items[0].metadata.name}')

    RUNNER_TOKEN=$(kubectl exec "$TOOLBOX_POD" -n ${var.namespace} -- gitlab-rails runner_registration_token | tail -n 1 | tr -d '\r')

    jq -n --arg token "$RUNNER_TOKEN" '{"token": $token}'
  EOT
  ]
}

resource "helm_release" "gitlab_runner" {
  depends_on = [data.external.gitlab_runner_token]

  name       = "gitlab-runner"
  repository = "https://charts.gitlab.io/"
  chart      = "gitlab-runner"
  namespace  = var.namespace
  version    = "0.70.0"

  values = [
    <<-YAML
    gitlabUrl: http://gitlab-webservice-default.${var.namespace}.svc.cluster.local:8181
    runnerRegistrationToken: ${data.external.gitlab_runner_token.result.token}
    runners:
      privileged: true
      executor: kubernetes
    YAML
  ]
}