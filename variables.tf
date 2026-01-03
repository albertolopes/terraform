variable "kubeconfig_path" {
  type        = string
  description = "Path to kubeconfig file for the kubernetes provider. If empty, ~/.kube/config will be used."
  default     = ""
}

variable "container_name" {
  type        = string
  description = "Name for the local Docker container created by Terraform"
  default     = "tutorial"
}

variable "nginx_image" {
  type        = string
  description = "Docker image for nginx deployment (can override via -var or terraform.tfvars)"
  default     = "nginx:1.29.4-alpine"
}

variable "postgres_image" {
  type        = string
  description = "Docker image for postgres deployment (overrideable)"
  default     = "postgres:15"
}

variable "postgres_host_path" {
  type        = string
  description = "Absolute host path to use for Postgres hostPath PV (used when use_local_path is false). If empty, repo-relative ./volume/postgres-data will be used."
  default     = ""
}

variable "use_local_path" {
  type        = bool
  description = "When true, use the local-path StorageClass (dynamic) instead of creating a hostPath PV"
  default     = true
}
