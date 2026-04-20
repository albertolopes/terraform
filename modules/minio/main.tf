resource "kubernetes_namespace_v1" "gitlab" {
  metadata {
    name = var.namespace
  }
}

# Secret para o GitLab acessar o MinIO
resource "kubectl_manifest" "gitlab_minio_secret" {
  yaml_body = <<-YAML
    apiVersion: v1
    kind: Secret
    metadata:
      name: gitlab-minio-secret
      namespace: ${var.namespace}
    type: Opaque
    stringData:
      connection: |
        [default]
        host = minio.default.svc.cluster.local:9000
        access_key = ${var.minio_access_key}
        secret_key = ${var.minio_secret_key}
        use_ssl = false
      accesskey: ${var.minio_access_key}
      secretkey: ${var.minio_secret_key}
  YAML
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

resource "helm_release" "gitlab" {
  name             = "gitlab"
  repository       = "https://charts.gitlab.io/"
  chart            = "gitlab"
  version          = var.chart_version
  namespace        = kubernetes_namespace_v1.gitlab.metadata[0].name
  timeout          = 1800
  create_namespace = false
  wait             = true
  wait_for_jobs    = true
  atomic           = true
  cleanup_on_fail  = true
  max_history      = 3

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
      # Desabilitar MinIO interno do GitLab
      minio:
        enabled: false
      appConfig:
        lfs:
          enabled: true
          bucket: gitlab-lfs
        artifacts:
          enabled: true
          bucket: gitlab-artifacts
        packages:
          enabled: true
          bucket: gitlab-packages
        uploads:
          enabled: true
          bucket: gitlab-uploads
        containerRegistry:
          enabled: false
        pseudonymizer:
          enabled: false
        object_store:
          enabled: true
          proxy_download: true
          connection:
            secret: gitlab-minio-secret
            key: connection

    certmanager:
      install: false

    prometheus:
      install: false

    gitlab-runner:
      install: false

    # Desabilitar MinIO interno
    minio:
      install: false
      enabled: false

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
          size: 8Gi

    gitlab:
      webservice:
        enabled: true
        minReplicas: 1
        maxReplicas: 1
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
          failureThreshold: 15
        readinessProbe:
          initialDelaySeconds: 300
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 15
        workerProcesses: 1
        persistence:
          enabled: false
        # Configurar object storage
        objectStorage:
          enabled: true
          config:
            secret: gitlab-minio-secret
            key: connection

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
          failureThreshold: 15
        readinessProbe:
          initialDelaySeconds: 300
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 15

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
          size: 20Gi
        service:
          port: 8075

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

      # Configurar buckets no MinIO
      initialBuckets:
        - gitlab-lfs
        - gitlab-artifacts
        - gitlab-uploads
        - gitlab-packages

    nginx:
      enabled: false

    gitlab-exporter:
      enabled: false
    YAML
  ]

  depends_on = [
    kubernetes_namespace_v1.gitlab,
    kubectl_manifest.gitlab_root_secret,
    kubectl_manifest.gitlab_postgres_secret,
    kubectl_manifest.gitlab_redis_secret,
    kubectl_manifest.gitlab_minio_secret,
  ]

  provisioner "local-exec" {
    when    = create
    command = <<-EOT
      echo "GitLab installation started..."
      echo "Monitor with: kubectl get pods -n ${var.namespace} -w"
      echo ""
      echo "Once ready, access at: http://gitlab.${var.domain_name}"
      echo "Username: root"
      echo "Password: ${var.root_password != null ? var.root_password : "changeme123"}"
      echo ""
      echo "MinIO buckets will be created automatically for:"
      echo "  - gitlab-lfs"
      echo "  - gitlab-artifacts"
      echo "  - gitlab-uploads"
      echo "  - gitlab-packages"
    EOT
  }
}

# Outputs
output "gitlab_url" {
  value = "http://gitlab.${var.domain_name}"
}

output "gitlab_status_command" {
  value = "kubectl get pods -n ${var.namespace}"
}

output "gitlab_logs_command" {
  value = "kubectl logs -n ${var.namespace} -l app=webservice --tail=100"
}
Como usar no seu main.tf:
hcl
# main.tf

terraform {
required_providers {
helm = {
source = "hashicorp/helm"
}
kubernetes = {
source = "hashicorp/kubernetes"
}
kubectl = {
source  = "gavinbunney/kubectl"
version = "~> 1.14"
}
}
}

# Configuração do MinIO (seu código existente)
variable "minio_access_key" {
description = "Minio root user"
type        = string
default     = "minioadmin"
}

variable "minio_secret_key" {
description = "Minio root password"
type        = string
sensitive   = true
default     = "minioadmin123"
}

variable "domain_name" {
description = "Base domain name"
type        = string
default     = "tail799250.ts.net"
}

resource "kubernetes_secret_v1" "minio_credentials" {
metadata {
name      = "minio-credentials"
namespace = "default"
}

data = {
rootUser     = base64encode(var.minio_access_key)
rootPassword = base64encode(var.minio_secret_key)
}
}

resource "helm_release" "minio" {
depends_on      = [kubernetes_secret_v1.minio_credentials]
name            = "minio"
repository      = "https://charts.bitnami.com/bitnami"
chart           = "minio"
namespace       = "default"
cleanup_on_fail = true
wait            = true
timeout         = 600

values = [
templatefile("${path.module}/values.yaml", {
domain_name = var.domain_name
})
]
}

# Módulo do GitLab usando o MinIO existente
module "gitlab" {
source = "./modules/gitlab"

namespace        = "gitlab"
domain_name      = var.domain_name
root_password    = "changeme123"
minio_access_key = var.minio_access_key
minio_secret_key = var.minio_secret_key

depends_on = [helm_release.minio]
}
values.yaml do MinIO (seu arquivo existente):
yaml
auth:
existingSecret: minio-credentials

service:
type: ClusterIP

defaultBuckets:
- terraform-state
- gitlab-lfs
- gitlab-artifacts
- gitlab-uploads
- gitlab-packages

ingress:
enabled: true
ingressClassName: traefik
hostname: minio.${domain_name}
path: /

extraEnvVars:
- name: MINIO_BROWSER_REDIRECT_URL
value: https://minio.${domain_name}