# --- SECRETS ---

resource "kubernetes_secret_v1" "gitlab_minio_secret" {
  metadata {
    name      = "gitlab-minio-secret"
    namespace = var.namespace
  }
  type = "Opaque"
  data = {
    "accesskey"  = var.minio_access_key
    "secretkey"  = var.minio_secret_key
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

# SECRET DO REGISTRY: Removidas aspas e unificado o endpoint para o serviço do MinIO
resource "kubernetes_secret_v1" "registry_storage_secret" {
  metadata {
    name      = "registry-storage-secret"
    namespace = var.namespace
  }
  type = "Opaque"
  data = {
    "config" = <<-EOT
s3:
  accesskey: ${var.minio_access_key}
  secretkey: ${var.minio_secret_key}
  region: us-east-1
  regionendpoint: http://minio.minio.svc.cluster.local:9000
  bucket: gitlab-registry
  v4auth: true
  secure: false
  pathstyle: true
redirect:
  disable: true
cache:
  blobdescriptor: inmemory
EOT
  }
}

resource "kubernetes_secret_v1" "gitlab_root_secret" {
  metadata {
    name      = "gitlab-root-secret"
    namespace = var.namespace
  }
  type = "Opaque"
  data = {
    "password" = var.root_password != null ? var.root_password : "changeme123"
  }
}

resource "kubernetes_secret_v1" "gitlab_external_postgres_password" {
  metadata {
    name      = "gitlab-external-postgres-password"
    namespace = var.namespace
  }
  type = "Opaque"
  data = {
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

resource "kubernetes_manifest" "gitlab_tls_certificate" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "gitlab-tls"
      namespace = var.namespace
    }
    spec = {
      secretName = "gitlab-tls"
      issuerRef = {
        name = "letsencrypt-cloudflare"
        kind = "ClusterIssuer"
      }
      dnsNames = [
        "gitlab.${var.domain_name}",
        "registry.${var.domain_name}",
        "kas.${var.domain_name}"
      ]
    }
  }
}

resource "null_resource" "wait_for_gitlab_tls_certificate" {
  depends_on = [kubernetes_manifest.gitlab_tls_certificate]

  provisioner "local-exec" {
    command = "kubectl wait --for=condition=Ready certificate/gitlab-tls -n ${var.namespace} --timeout=900s"
    environment = {
      KUBECONFIG = "${path.cwd}/.k3d_kubeconfig"
    }
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
    kubernetes_secret_v1.registry_storage_secret,
    null_resource.wait_for_gitlab_tls_certificate
  ]

  values = [
    <<-YAML
    global:
      edition: ce
      ingress:
        enabled: true
        provider: traefik
        class: traefik
        configureCertmanager: false
        tls:
          enabled: true
          secretName: gitlab-tls
        annotations:
          kubernetes.io/ingress.class: "traefik"
          traefik.ingress.kubernetes.io/router.middlewares: "${var.namespace}-traefik-force-https-header@kubernetescrd"
      hosts:
        domain: ${var.domain_name}
        gitlab:
          name: gitlab.${var.domain_name}
        registry:
          name: registry.${var.domain_name}
        https: true

      initialRootPassword:
        secret: gitlab-root-secret
        key: password

      registry:
        enabled: true
        bucket: "gitlab-registry"
        issuer: "gitlab-issuer"

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

      rails:
        bootsnap:
          enabled: false

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
        workerProcesses: 0
        puma:
          threads:
            min: 1
            max: 2
        deployment:
          readinessProbe:
            initialDelaySeconds: 0
            timeoutSeconds: 10
            failureThreshold: 60
          livenessProbe:
            initialDelaySeconds: 1800
            timeoutSeconds: 10
            failureThreshold: 30
        workhorse:
          readinessProbe:
            timeoutSeconds: 10
            failureThreshold: 6
          livenessProbe:
            timeoutSeconds: 30
            failureThreshold: 6
        resources:
          requests:
            cpu: 800m
            memory: 2Gi
          limits:
            cpu: 3000m
            memory: 6Gi
      sidekiq:
        minReplicas: 1
        maxReplicas: 1
        resources:
          requests:
            cpu: 300m
            memory: 1Gi
          limits:
            cpu: 1500m
            memory: 2Gi
      toolbox:
        resources:
          requests:
            cpu: 300m
            memory: 1Gi
          limits:
            cpu: 1000m
            memory: 2Gi
        backups:
          objectStorage:
            config:
              secret: gitlab-minio-secret
              key: connection
      gitaly:
        statefulset:
          readinessProbe:
            timeoutSeconds: 10
            failureThreshold: 6
          livenessProbe:
            timeoutSeconds: 10
            failureThreshold: 6
          startupProbe:
            timeoutSeconds: 10
        resources:
          requests:
            cpu: 1000m
            memory: 2Gi
          limits:
            cpu: 3000m
            memory: 3Gi
        persistence:
          enabled: true
          storageClass: "local-path"
          size: 50Gi
      gitlab-shell:
        minReplicas: 1
        maxReplicas: 1
        deployment:
          readinessProbe:
            timeoutSeconds: 10
            failureThreshold: 6
          livenessProbe:
            timeoutSeconds: 10
            failureThreshold: 6

    gitlab-kas:
      minReplicas: 1
      maxReplicas: 1

    # CONFIGURAÇÃO DO REGISTRY (Fora do global)
    registry:
      enabled: true
      annotations:
        registry.gitlab.com/storage-bucket: "gitlab-registry"
      ingress:
        proxyReadTimeout: 1800
        proxyBodySize: "0"
        proxyBuffering: "off"
        annotations:
          traefik.ingress.kubernetes.io/router.middlewares: "${var.namespace}-traefik-force-https-header@kubernetescrd"
      hpa:
        minReplicas: 1
        maxReplicas: 1
      deployment:
        readinessProbe:
          timeoutSeconds: 10
          failureThreshold: 6
        livenessProbe:
          timeoutSeconds: 10
          failureThreshold: 6
      resources:
        requests:
          cpu: 200m
          memory: 512Mi
        limits:
          cpu: 1000m
          memory: 1Gi
      storage:
        secret: "registry-storage-secret"
        key: "config"
      authEndpoint: "https://gitlab.${var.domain_name}"
      tokenIssuer: "gitlab-issuer"

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
    api_groups = [""]
    resources  = ["pods", "pods/exec", "pods/attach", "pods/status", "secrets", "configmaps", "services"]
    verbs      = ["get", "list", "watch", "create", "delete", "update", "patch"]
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments"]
    verbs      = ["get", "list", "watch", "create", "delete", "update", "patch"]
  }

  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["ingresses"]
    verbs      = ["get", "list", "watch", "create", "delete", "update", "patch"]
  }

  rule {
    api_groups = [""]
    resources  = ["pods/log"]
    verbs      = ["get", "list"]
  }

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

resource "kubernetes_cluster_role_v1" "gitlab_runner_dynamic_deployer_role" {
  metadata {
    name = "gitlab-runner-dynamic-deployer-role"
  }

  rule {
    api_groups = [""]
    resources  = ["namespaces"]
    verbs      = ["get", "list", "watch", "create", "update", "patch"]
  }

  rule {
    api_groups = [""]
    resources  = ["services", "configmaps", "secrets"]
    verbs      = ["get", "list", "watch", "create", "delete", "update", "patch"]
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments"]
    verbs      = ["get", "list", "watch", "create", "delete", "update", "patch"]
  }

  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["ingresses"]
    verbs      = ["get", "list", "watch", "create", "delete", "update", "patch"]
  }
}

resource "kubernetes_cluster_role_binding_v1" "gitlab_runner_dynamic_deployer_role_binding" {
  metadata {
    name = "gitlab-runner-dynamic-deployer-role-binding"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.gitlab_runner_dynamic_deployer_role.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = "default"
    namespace = var.namespace
  }
}

# --- NAMESPACE DA APLICAÇÃO CRIPTO PRICE ---

resource "kubernetes_namespace_v1" "cripto_price" {
  metadata {
    name = "cripto-price"
  }
}

resource "kubernetes_role_v1" "cripto_price_deployer_role" {
  metadata {
    name      = "cripto-price-deployer-role"
    namespace = kubernetes_namespace_v1.cripto_price.metadata[0].name
  }

  rule {
    api_groups = [""]
    resources  = ["services", "configmaps", "secrets"]
    verbs      = ["get", "list", "watch", "create", "delete", "update", "patch"]
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments"]
    verbs      = ["get", "list", "watch", "create", "delete", "update", "patch"]
  }

  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["ingresses"]
    verbs      = ["get", "list", "watch", "create", "delete", "update", "patch"]
  }
}

resource "kubernetes_role_binding_v1" "cripto_price_deployer_role_binding" {
  metadata {
    name      = "cripto-price-deployer-role-binding"
    namespace = kubernetes_namespace_v1.cripto_price.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.cripto_price_deployer_role.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = "default"
    namespace = var.namespace
  }
}

# --- HELM RELEASE GITLAB RUNNER ---

resource "helm_release" "gitlab_runner" {
  depends_on = [
    null_resource.wait_for_gitlab_webservice,
    kubernetes_role_binding_v1.gitlab_runner_role_binding,
    kubernetes_cluster_role_binding_v1.gitlab_runner_dynamic_deployer_role_binding,
    kubernetes_role_binding_v1.cripto_price_deployer_role_binding
  ]

  name      = "gitlab-runner"
  chart     = "${path.module}/gitlab/charts/gitlab-runner"
  namespace = var.namespace

  values = [
    <<-YAML
    gitlabUrl: http://gitlab-webservice-default.${var.namespace}.svc.cluster.local:8181
    runnerToken: "${var.runner_authentication_token}"
    concurrent: 1
    checkInterval: 10

    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 3000m
        memory: 3Gi

    runners:
      config: |
        [[runners]]
          environment = [
            "DOCKER_HOST=tcp://docker:2375",
            "DOCKER_TLS_CERTDIR=",
            "DOCKER_DRIVER=vfs",
            "DOCKER_BUILDKIT=1"
          ]
          [runners.kubernetes]
            image = "docker:25.0.5"
            privileged = true
            services_privileged = true
            poll_timeout = 600
            clone_url = "http://gitlab-webservice-default.${var.namespace}.svc.cluster.local:8181"
            cpu_request = "500m"
            memory_request = "1Gi"
            cpu_limit = "1000m"
            memory_limit = "2Gi"
            helper_cpu_request = "100m"
            helper_memory_request = "128Mi"
            service_cpu_request = "400m"
            service_memory_request = "1Gi"
          [runners.cache]
            Type = "s3"
            Path = "gitlab-runner"
            Shared = true
          [runners.cache.s3]
            ServerAddress = "minio.minio.svc.cluster.local:9000"
            AccessKey = "${var.minio_access_key}"
            SecretKey = "${var.minio_secret_key}"
            BucketName = "runner-cache"
            BucketLocation = "us-east-1"
            Insecure = true
            AuthenticationType = "access-key"
            PathStyle = true
          [[runners.kubernetes.host_aliases]]
            ip = "${var.traefik_service_cluster_ip}"
            hostnames = ["registry.${var.domain_name}"]

      privileged: true
      executor: kubernetes
      tags: "desenv,homolog,production"
      runUntagged: true
      protected: false
      locked: false
    YAML
  ]
}
