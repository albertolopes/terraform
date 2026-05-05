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
    "password" = var.redis_password
  }
}

resource "kubernetes_secret_v1" "registry_storage_secret" {
  metadata {
    name      = "registry-storage-secret"
    namespace = var.namespace
  }
  type = "Opaque"
  data = {
    # Usando 'config' como chave e aspas nos valores para evitar erro de parse
    "config" = base64encode(<<-EOT
      s3:
        accesskey: "${var.minio_access_key}"
        secretkey: "${var.minio_secret_key}"
        region: "us-east-1"
        regionendpoint: "http://minio.minio.svc.cluster.local:9000"
        bucket: "registry"
        v4auth: true
        secure: false
        pathstyle: true
      EOT
    )
  }
}

# --- HELM RELEASE GITLAB ---

resource "helm_release" "gitlab" {
  name      = "gitlab"
  chart     = "${path.module}/gitlab"
  version   = "9.0.0"
  namespace = var.namespace

  timeout         = 1800
  wait            = true
  wait_for_jobs   = false
  cleanup_on_fail = true
  max_history     = 3

  depends_on = [
    kubernetes_secret_v1.gitlab_external_postgres_password,
    kubernetes_secret_v1.gitlab_root_secret,
    kubernetes_secret_v1.gitlab_redis_password,
    kubernetes_secret_v1.gitlab_minio_secret,
    kubernetes_secret_v1.registry_storage_secret
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
      registry:
        enabled: true
        bucket: "registry"

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
      enabled: true
      hpa:
        minReplicas: 1
        maxReplicas: 1
      storage:
        secret: "registry-storage-secret"
        key: "config"
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

# --- RBAC: PERMISSÕES PARA O RUNNER ---

resource "kubernetes_role_v1" "gitlab_runner_role" {
  metadata {
    name      = "gitlab-runner-role"
    namespace = var.namespace
  }

  rule {
    # Adicionado "pods/attach" e "pods/status" para permitir a estratégia de execução do GitLab
    api_groups = [""]
    resources  = ["pods", "pods/exec", "pods/attach", "pods/status", "secrets", "configmaps"]
    verbs      = ["get", "list", "watch", "create", "delete", "update", "patch"]
  }

  rule {
    api_groups = [""]
    resources  = ["pods/log"]
    verbs      = ["get", "list"]
  }

  # Necessário para o executor Kubernetes gerenciar os eventos dos pods de build
  rule {
    api_groups = [""]
    resources  = ["events"]
    verbs      = ["watch", "list"]
  }
}

resource "kubernetes_role_binding_v1" "gitlab_runner_role_binding" {
  metadata {
    name      = "gitlab-runner-role-binding"
    namespace = var.namespace
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.gitlab_runner_role.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = "default"
    namespace = var.namespace
  }
}

# --- EXTRAÇÃO DO TOKEN ---

data "external" "gitlab_runner_token" {
  depends_on = [null_resource.wait_for_gitlab_webservice]

  program = ["bash", "-c", <<-EOT
    export KUBECONFIG="${path.cwd}/.k3d_kubeconfig"
    set -euo pipefail

    # 1. Tenta encontrar o pod usando o label novo (toolbox) ou o antigo (task-runner)
    TOOLBOX_POD=$(kubectl get pod -l app=toolbox,release=gitlab -n ${var.namespace} -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [ -z "$TOOLBOX_POD" ]; then
      TOOLBOX_POD=$(kubectl get pod -l app=task-runner,release=gitlab -n ${var.namespace} -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    fi

    # 2. Se o pod não existir (pods parados), retorna um JSON vazio para não quebrar o Terraform
    # Mas avisamos no stderr para você saber o que houve
    if [ -z "$TOOLBOX_POD" ]; then
       echo "ERRO: Nenhum pod de toolbox/task-runner encontrado no namespace ${var.namespace}. Garanta que o GitLab esteja rodando." >&2
       echo '{"token": ""}'
       exit 0
    fi

    # 3. Aguarda o pod ficar pronto (caso esteja subindo)
    kubectl wait --for=condition=ready pod "$TOOLBOX_POD" -n ${var.namespace} --timeout=60s > /dev/null 2>&1 || true

    # 4. Extrai o token
    RUNNER_TOKEN=$(kubectl exec "$TOOLBOX_POD" -n ${var.namespace} -c toolbox -- gitlab-rails runner "puts ApplicationSetting.current.runners_registration_token" 2>/dev/null | tail -n 1 | tr -d '\r' || echo "")

    # 5. Retorna o JSON obrigatório para o Terraform
    jq -n --arg token "$RUNNER_TOKEN" '{"token": $token}'
  EOT
  ]
}

# --- HELM RELEASE GITLAB RUNNER ---

resource "helm_release" "gitlab_runner" {
  depends_on = [
    data.external.gitlab_runner_token,
    kubernetes_role_binding_v1.gitlab_runner_role_binding
  ]

  name       = "gitlab-runner"
  repository = "https://charts.gitlab.io/"
  chart      = "gitlab-runner"
  namespace  = var.namespace
  version    = "0.70.0"

  values = [
    <<-YAML
    gitlabUrl: http://gitlab-webservice-default.${var.namespace}.svc.cluster.local:8181
    runnerRegistrationToken: ${data.external.gitlab_runner_token.result.token}

    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 200m
        memory: 1.5Gi

    runners:
      config: |
        [[runners]]
          [runners.kubernetes]
            image = "docker:25.0"
            privileged = true
            poll_timeout = 600

            # Permite usar as estratégias de Git nativas do GitLab sem falha de DNS/Túnel
            clone_url = "http://gitlab-webservice-default.${var.namespace}.svc.cluster.local:8181"

            # Recursos para os containers de build
            cpu_request = "500m"
            memory_request = "1Gi"
            cpu_limit = "1000m"
            memory_limit = "2Gi"

            # Recursos para o container helper
            helper_cpu_request = "100m"
            helper_memory_request = "128Mi"

            # Recursos para o DinD (svc-0)
            service_cpu_request = "400m"
            service_memory_request = "1Gi"

      privileged: true
      executor: kubernetes
      runUntagged: true
    YAML
  ]
}