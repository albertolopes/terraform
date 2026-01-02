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
