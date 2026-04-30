# modules/gitlab/variables.tf

variable "namespace" {
  type = string
}

variable "domain_name" {
  type = string
}

variable "chart_version" {
  type = string
}

variable "redis_password" {
  type = string
}

variable "postgres_password" {
  type = string
}

variable "minio_access_key" {
  type = string
}

variable "minio_secret_key" {
  type = string
}

variable "root_password" {
  type    = string
  default = null
}

variable "runner_authentication_token" {
  type = string
}