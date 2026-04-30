# modules/gitlab/variables.tf

variable "namespace" {
  description = "Kubernetes namespace for GitLab"
  type        = string
  default     = "gitlab"
}

variable "domain_name" {
  description = "Domain name for GitLab access (ex: gitlab.avocadotech.site)"
  type        = string
}

variable "root_password" {
  description = "GitLab initial root password"
  type        = string
  default     = null
  sensitive   = true
}

variable "gitlab_version" {
  description = "GitLab image tag (ex: 18.0.0-ce.0)"
  type        = string
  default     = "18.0.0"
}

variable "chart_version" {
  description = "GitLab Helm chart version"
  type        = string
  default     = "9.0.0"
}

variable "minio_access_key" {
  description = "Access key for MinIO object storage"
  type        = string
  default     = "minioadmin"
}

variable "minio_secret_key" {
  description = "Secret key for MinIO object storage"
  type        = string
  sensitive   = true
  default     = "minioadmin123"
}

variable "redis_password" {
  description = "Password for the Redis instance"
  type        = string
  sensitive   = true
}

variable "runner_authentication_token" {
  description = "GitLab Runner authentication token (starts with glrt-)"
  type        = string
  sensitive   = true
}

variable "trusted_proxies" {
  description = "List of trusted proxy IP ranges (K3d internal networks)"
  type        = list(string)
  default     = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "127.0.0.1"]
}