# modules/gitlab/main.tf

resource "kubernetes_namespace_v1" "gitlab" {
  metadata {
    name = var.namespace
  }
}

# ===== SECRETS =====

# Secret para o PostgreSQL (formato que o GitLab espera)
resource "kubernetes_secret_v1" "postgresql_password" {
  metadata {
    name      = "postgresql-password"
    namespace = kubernetes_namespace_v1.gitlab.metadata[0].name
  }

  data = {
    postgresql-password         = base64encode("postgres")
    postgresql-postgres-password = base64encode("postgres")
  }

  type = "Opaque"
}

# Secret para a senha root do GitLab
resource "kubernetes_secret_v1" "gitlab_root_secret" {
  metadata {
    name      = "gitlab-root-secret"
    namespace = kubernetes_namespace_v1.gitlab.metadata[0].name
  }

  data = {
    password = var.root_password != null ? base64encode(var.root_password) : base64encode("changeme123")
  }

  type = "Opaque"
}

# Secret para o PostgreSQL externo
resource "kubernetes_secret_v1" "gitlab_postgres_secret" {
  metadata {
    name      = "gitlab-postgres-secret"
    namespace = kubernetes_namespace_v1.gitlab.metadata[0].name
  }

  data = {
    password = base64encode("postgres")
  }

  type = "Opaque"
}

# Secret para o Redis
resource "kubernetes_secret_v1" "gitlab_redis_secret" {
  metadata {
    name      = "gitlab-redis-secret"
    namespace = kubernetes_namespace_v1.gitlab.metadata[0].name
  }

  data = {
    redis-password = base64encode("gitlab-redis-password")
  }

  type = "Opaque"
}

# ===== MINIO SECRETS =====
resource "kubernetes_secret_v1" "gitlab_minio_secret" {
  metadata {
    name      = "gitlab-minio-secret"
    namespace = kubernetes_namespace_v1.gitlab.metadata[0].name
  }

  data = {
    accesskey = base64encode("minioadmin")
    secretkey = base64encode("minioadmin123")
  }

  type = "Opaque"
}

# ===== HELM RELEASE =====
resource "helm_release" "gitlab" {
  name       = "gitlab"
  repository = "https://charts.gitlab.io"
  chart      = "gitlab"
  namespace  = kubernetes_namespace_v1.gitlab.metadata[0].name
  timeout    = 600

  # Usar values YAML para maior controle
  values = [
    <<-YAML
    # ===== COMPONENTES HABILITADOS =====
    certmanager:
      install: true
      email: albertolopes@mail.com

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

    # ===== POSTGRESQL EXTERNO =====
    postgresql:
      install: false

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

    # ===== REDIS INTERNO =====
    redis:
      install: true
      auth:
        existingSecret: gitlab-redis-secret
        enabled: true

    # ===== RECURSOS MÍNIMOS =====
    gitlab:
      webservice:
        minReplicas: 1
        maxReplicas: 1
        resources:
          requests:
            cpu: 200m
            memory: 512Mi

      sidekiq:
        minReplicas: 1
        maxReplicas: 1
        resources:
          requests:
            cpu: 100m
            memory: 256Mi

      gitaly:
        resources:
          requests:
            cpu: 100m
            memory: 256Mi

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

      toolbox:
        enabled: true

      migrations:
        enabled: true
    YAML
  ]

  depends_on = [
    kubernetes_namespace_v1.gitlab,
    kubernetes_secret_v1.postgresql_password,
    kubernetes_secret_v1.gitlab_root_secret,
    kubernetes_secret_v1.gitlab_postgres_secret,
    kubernetes_secret_v1.gitlab_redis_secret,
    kubernetes_secret_v1.gitlab_minio_secret
  ]
}