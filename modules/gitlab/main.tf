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

  data = {
    password = var.postgres_password_secret_data # Recebe a senha base64-encoded do módulo postgres
  }
  type = "Opaque"
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
  name      = "gitlab"
  chart     = "${path.module}/gitlab"
  version   = "9.0.0"
  namespace = var.namespace

  timeout         = 1800
  wait            = true # Changed to true to wait for GitLab to be ready
  wait_for_jobs   = false
  cleanup_on_fail = true
  atomic          = false
  max_history     = 3

  depends_on = [
    kubernetes_secret_v1.gitlab_external_postgres_password, # Nova dependência para o secret da senha do Postgres
    kubernetes_secret_v1.gitlab_root_secret,
    kubernetes_secret_v1.gitlab_redis_password,
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
          name: ${var.domain_name}
        https: true

      redis:
        host: redis.redis.svc.cluster.local
        port: 6379
        password:
          secret: gitlab-redis-password
          key: password

      # Configuração para usar o PostgreSQL externo
      psql:
        host: postgres.postgres.svc.cluster.local # Nome do serviço PostgreSQL no namespace 'postgres'
        port: 5433
        username: postgres # Usuário configurado no módulo postgres
        database: gitlabhq_production # Banco de dados para o GitLab
        password:
          secret: gitlab-external-postgres-password # Nome do secret que criamos
          key: password # Chave dentro do secret que contém a senha

    # Desativa componentes internos para usar os externos (ou economizar RAM)
    certmanager: { install: false }
    certmanager-issuer: { install: false }
    redis: { install: false }
    postgresql: { install: false } # Desativa o PostgreSQL interno, pois usaremos o externo
    nginx-ingress: { enabled: false }
    prometheus: { install: false }
    gitlab-runner: { install: false }

    # Otimização de recursos para k3d local
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

# --- Wait for GitLab Webservice to be available ---
resource "null_resource" "wait_for_gitlab_webservice" {
  depends_on = [helm_release.gitlab]

  provisioner "local-exec" {
    command = "kubectl wait --for=condition=available deployment/gitlab-webservice-default -n ${var.namespace} --timeout=900s"
    environment = {
      KUBECONFIG = "${path.cwd}/.k3d_kubeconfig"
    }
  }
}

# --- Retrieve GitLab Runner Token ---
resource "null_resource" "get_gitlab_runner_token" {
  depends_on = [null_resource.wait_for_gitlab_webservice]

  provisioner "local-exec" {
    command = <<EOT
      set -euo pipefail

      echo "Waiting for GitLab toolbox pod to be ready..."
      kubectl wait --for=condition=ready pod -l app=toolbox,release=gitlab -n ${var.namespace} --timeout=600s

      TOOLBOX_POD=$(kubectl get pod -l app=toolbox,release=gitlab -n ${var.namespace} -o jsonpath='{.items[0].metadata.name}')
      if [ -z "$TOOLBOX_POD" ]; then
        echo "Error: GitLab toolbox pod not found." >&2
        exit 1
      fi

      echo "Retrieving GitLab Runner registration token from $TOOLBOX_POD..."
      RUNNER_TOKEN=$(kubectl exec -it "$TOOLBOX_POD" -n ${var.namespace} -- gitlab-rails runner_registration_token)
      if [ -z "$RUNNER_TOKEN" ]; then
        echo "Error: Failed to retrieve GitLab Runner token." >&2
        exit 1
      fi

      echo "$RUNNER_TOKEN" > "${path.module}/.gitlab_runner_token"
      echo "GitLab Runner token saved to ${path.module}/.gitlab_runner_token"
    EOT
    environment = {
      KUBECONFIG = "${path.cwd}/.k3d_kubeconfig"
    }
  }

  triggers = {
    gitlab_release_version = helm_release.gitlab.version
  }
}

# --- GITLAB RUNNER ---

resource "helm_release" "gitlab_runner" {
  depends_on = [
    helm_release.gitlab,
    null_resource.get_gitlab_runner_token # Now depends on getting the token
  ]
  name       = "gitlab-runner"
  repository = "https://charts.gitlab.io/"
  chart      = "gitlab-runner"
  namespace  = var.namespace
  version    = "0.70.0"
  timeout    = 900 # Increased timeout to 15 minutes

  values = [
    <<-YAML
    gitlabUrl: http://gitlab-webservice-default.${var.namespace}.svc.cluster.local:8181
    runnerToken: ${file("${path.module}/.gitlab_runner_token")} # Read token from file
    runners:
      privileged: true
      executor: kubernetes
    YAML
  ]
}