# modules/gitlab/main.tf

resource "kubernetes_namespace_v1" "gitlab" {
  metadata {
    name = var.namespace
  }
}

resource "helm_release" "gitlab" {
  name       = "gitlab"
  repository = "https://charts.gitlab.io"
  chart      = "gitlab"
  namespace  = kubernetes_namespace_v1.gitlab.metadata[0].name
  timeout    = 600

  # ===== DOMÍNIO =====
  set {
    name  = "global.hosts.domain"
    value = var.domain_name
  }
  set {
    name  = "global.hosts.https"
    value = "false"
  }

  # ===== INGRESS =====
  set {
    name  = "global.ingress.enabled"
    value = "true"
  }
  set {
    name  = "global.ingress.class"
    value = "traefik"
  }
  set {
    name  = "global.ingress.createIngressClass"
    value = "false"
  }
  set {
    name  = "global.ingress.tls.enabled"
    value = "false"
  }

  # ===== SENHA ROOT =====
  set {
    name  = "global.initialRootPassword.secret"
    value = "gitlab-root-secret"
  }

  # ===== POSTGRESQL EXTERNO =====
  set {
    name  = "postgresql.install"
    value = "false"
  }
  set {
    name  = "global.psql.host"
    value = "postgres.postgres.svc.cluster.local"
  }
  set {
    name  = "global.psql.port"
    value = "5433"
  }
  set {
    name  = "global.psql.username"
    value = "postgres"
  }
  set {
    name  = "global.psql.password.secret"
    value = "gitlab-postgres-secret"
  }
  set {
    name  = "global.psql.database"
    value = "gitlabhq_production"
  }

  # ===== REDIS INTERNO =====
  set {
    name  = "redis.install"
    value = "true"
  }
  set {
    name  = "redis.auth.password"
    value = "gitlab-redis-password"
  }

  # ===== RECURSOS MÍNIMOS =====
  set {
    name  = "gitlab.webservice.minReplicas"
    value = "1"
  }
  set {
    name  = "gitlab.webservice.maxReplicas"
    value = "1"
  }
  set {
    name  = "gitlab.sidekiq.minReplicas"
    value = "1"
  }
  set {
    name  = "gitlab.sidekiq.maxReplicas"
    value = "1"
  }

  # ===== DESABILITAR COMPONENTES (SINTAXE CORRETA) =====
  set {
    name  = "gitlab-runner.install"
    value = "false"
  }
  set {
    name  = "minio.install"
    value = "false"
  }
  set {
    name  = "registry.enabled"
    value = "false"
  }
  set {
    name  = "prometheus.install"
    value = "false"
  }

  depends_on = [kubernetes_namespace_v1.gitlab]
}

# ===== SECRETS =====
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