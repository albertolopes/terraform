# modules/gitlab/variables.tf

variable "namespace" {
  description = "Kubernetes namespace for GitLab"
  type        = string
  default     = "gitlab"
}

variable "domain_name" {
  description = "Domain name for GitLab access"
  type        = string
}

variable "root_password" {
  description = "GitLab root password"
  type        = string
  default     = null
  sensitive   = true
}

variable "gitlab_version" {
  description = "GitLab version to install"
  type        = string
  default     = "17.9.0"
}

variable "chart_version" {
  description = "GitLab Helm chart version"
  type        = string
  default     = "8.4.0"
}

variable "minio_access_key" {
  description = "MinIO access key"
  type        = string
  default     = "minioadmin"
}

variable "minio_secret_key" {
  description = "MinIO secret key"
  type        = string
  sensitive   = true
  default     = "minioadmin123"
}

variable "redis_password" {
  description = "Redis password"
  type        = string
  sensitive   = true
}

variable "runner_registration_token" {
  description = "GitLab Runner registration token"
  type        = string
  sensitive   = true
  default     = ""
}