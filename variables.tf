# variables.tf (raiz do projeto)

variable "domain_name" {
  description = "Domínio principal"
  type        = string
  default     = "avocadotech.site" # Voltando para o domínio real
}

variable "admin_email" {
  description = "Email do administrador"
  type        = string
  default     = "albertolopes@mail.com"
}

variable "gitlab_root_password" {
  description = "Senha inicial do root do GitLab"
  type        = string
  sensitive   = true
  default     = "changeme123"
}

variable "minio_access_key" {
  description = "Access key do MinIO"
  type        = string
  default     = "minioadmin"
}

variable "minio_secret_key" {
  description = "Secret key do MinIO"
  type        = string
  sensitive   = true
  default     = "minioadmin123"
}

variable "redis_password" {
  description = "Redis password for GitLab"
  type        = string
  sensitive   = true
  # ATENÇÃO: Se o seu Redis Alpine exige uma senha diferente,
  # mude aqui ou passe via terraform.tfvars.
  default = "gitlab-redis-password"
}

variable "postgres_password" {
  description = "Senha do banco PostgreSQL externo"
  type        = string
  sensitive   = true
  # ATENÇÃO: Coloque aqui a senha real que o seu PostgreSQL espera na porta 5433
  default = "postgres"
}

variable "pgadmin_hostname" {
  description = "Subdominio publico do pgAdmin."
  type        = string
  default     = "pgadmin"
}

variable "pgadmin_email" {
  description = "Email inicial de login do pgAdmin."
  type        = string
  default     = "admin@avocadotech.site"
}

variable "pgadmin_password" {
  description = "Senha inicial de login do pgAdmin."
  type        = string
  sensitive   = true
  default     = "pgadmin123"
}

variable "pgadmin_storage_size" {
  description = "Tamanho do volume persistente do pgAdmin."
  type        = string
  default     = "2Gi"
}

variable "pgadmin_enable_ingress" {
  description = "Habilita Ingress publico para o pgAdmin."
  type        = bool
  default     = true
}

variable "gitlab_runner_token" {
  description = "GitLab Runner authentication token"
  type        = string
  sensitive   = true
  default     = "glrt-5e3ec77772cda317786173d3d0e157f7686a24be"
}

variable "tesseract_api_image" {
  description = "Imagem da API Tesseract ja disponivel no cluster ou registry"
  type        = string
  default     = "tesseract-api:latest"
}

variable "tesseract_ocr_image" {
  description = "Imagem do servico Tesseract OCR ja disponivel no cluster ou registry"
  type        = string
  default     = "tesseract-ocr:latest"
}

variable "tesseract_hostname" {
  description = "Subdominio publico da API Tesseract"
  type        = string
  default     = "tesseract"
}

variable "tesseract_api_build_context" {
  description = "Diretorio com o Dockerfile da API Tesseract para build/import local no k3d. Use null para nao buildar."
  type        = string
  default     = null
}

variable "tesseract_api_dockerfile" {
  description = "Dockerfile usado para build da API Tesseract. Use null para usar o Dockerfile do contexto."
  type        = string
  default     = null
}

variable "tesseract_ocr_build_context" {
  description = "Diretorio com o Dockerfile do Tesseract OCR para build/import local no k3d. Use null para nao buildar."
  type        = string
  default     = null
}

variable "tesseract_api_replicas" {
  description = "Quantidade de replicas da API Tesseract."
  type        = number
  default     = 1
}

variable "tesseract_enable_ingress" {
  description = "Habilita Certificate/Ingress publico para a API Tesseract."
  type        = bool
  default     = true
}

variable "uptime_kuma_hostname" {
  description = "Subdominio publico do Uptime Kuma."
  type        = string
  default     = "uptime"
}

variable "uptime_kuma_image" {
  description = "Imagem do Uptime Kuma."
  type        = string
  default     = "louislam/uptime-kuma:1"
}

variable "uptime_kuma_storage_size" {
  description = "Tamanho do volume persistente do Uptime Kuma."
  type        = string
  default     = "5Gi"
}

variable "uptime_kuma_enable_ingress" {
  description = "Habilita Ingress publico para o Uptime Kuma."
  type        = bool
  default     = true
}

variable "uptime_kuma_enable_certificate" {
  description = "Habilita Certificate/TLS via cert-manager para o Uptime Kuma."
  type        = bool
  default     = false
}

variable "mail_hostname" {
  description = "Subdominio dos protocolos SMTP/IMAP/JMAP do Stalwart."
  type        = string
  default     = "mail"
}

variable "mail_webmail_hostname" {
  description = "Subdominio do webmail SnappyMail."
  type        = string
  default     = "webmail"
}

variable "mail_admin_hostname" {
  description = "Subdominio da administracao do Stalwart."
  type        = string
  default     = "admin-mail"
}

variable "mail_stalwart_storage_size" {
  description = "Tamanho do PVC de dados do Stalwart."
  type        = string
  default     = "50Gi"
}

variable "mail_snappymail_storage_size" {
  description = "Tamanho do PVC de dados/configuracao do SnappyMail."
  type        = string
  default     = "5Gi"
}

variable "mail_server_ipv4" {
  description = "IPv4 publico para mail.<dominio>. Sem este valor, MX/SPF/DMARC nao sao criados."
  type        = string
  default     = ""
}

variable "mail_server_ipv6" {
  description = "IPv6 publico para mail.<dominio>, se utilizado."
  type        = string
  default     = ""
}

variable "kubernetes_config_path" {
  description = "Caminho do kubeconfig usado pelos providers Kubernetes, Helm e Kubectl. Use null para .k3d_kubeconfig local."
  type        = string
  default     = null
}

variable "kubernetes_host" {
  description = "Endpoint da API Kubernetes. Use null para respeitar o server definido no kubeconfig."
  type        = string
  default     = null
}

variable "cloudflare_api_token" {
  description = "Cloudflare API Token"
  type        = string
  sensitive   = true
}

variable "cloudflare_account_id" {
  description = "Cloudflare Account ID"
  type        = string
}

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID"
  type        = string
}

variable "backup_device" {
  description = "Particao dedicada para backups. Protecoes impedem uso de /dev/sda* e /dev/sdb*."
  type        = string
  default     = "/dev/sdc2"
}

variable "backup_mount_point" {
  description = "Ponto de montagem persistente do disco de backup no host."
  type        = string
  default     = "/backup"
}

variable "backup_directories" {
  description = "Diretorios criados no disco de backup."
  type        = list(string)
  default = [
    "/backup/gitlab",
    "/backup/postgres",
    "/backup/minio",
    "/backup/registry",
    "/backup/logs"
  ]
}

variable "gitlab_backup_host_path" {
  description = "Diretorio do host exposto ao Kubernetes para armazenar backups finais do GitLab."
  type        = string
  default     = "/backup/gitlab"
}

variable "gitlab_backup_container_mount_path" {
  description = "Caminho montado dentro dos pods dos CronJobs de backup/limpeza."
  type        = string
  default     = "/backup/gitlab"
}

variable "gitlab_backup_schedule" {
  description = "Agendamento cron do backup diario do GitLab."
  type        = string
  default     = "0 2 * * *"
}

variable "gitlab_backup_cleanup_schedule" {
  description = "Agendamento cron da limpeza de backups antigos do GitLab."
  type        = string
  default     = "30 3 * * *"
}

variable "gitlab_backup_retention_days" {
  description = "Quantidade de dias para manter arquivos *_gitlab_backup.tar em /backup/gitlab."
  type        = number
  default     = 30
}

variable "gitlab_toolbox_label_selector" {
  description = "Label selector usado para localizar dinamicamente o pod gitlab-toolbox."
  type        = string
  default     = "app=toolbox,release=gitlab"
}

variable "gitlab_backup_kubectl_image" {
  description = "Imagem usada pelo CronJob customizado para executar kubectl exec no toolbox."
  type        = string
  default     = "bitnami/kubectl:1.30"
}

variable "k3d_cluster_name" {
  description = "Nome do cluster k3d usado para validar se /backup esta bind-mounted nos nodes locais."
  type        = string
  default     = "mycluster"
}
