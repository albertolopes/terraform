variable "namespace" {
  description = "Namespace Kubernetes para os servicos Tesseract."
  type        = string
  default     = "tesseract"
}

variable "domain_name" {
  description = "Dominio base usado no ingress da API."
  type        = string
}

variable "hostname" {
  description = "Subdominio da API Tesseract."
  type        = string
  default     = "tesseract"
}

variable "api_image" {
  description = "Imagem da API Tesseract ja disponivel no cluster ou registry."
  type        = string
  default     = "tesseract-api:latest"
}

variable "tesseract_ocr_image" {
  description = "Imagem do servico Tesseract OCR ja disponivel no cluster ou registry."
  type        = string
  default     = "tesseract-ocr:latest"
}

variable "image_pull_policy" {
  description = "Politica de pull das imagens."
  type        = string
  default     = "IfNotPresent"
}

variable "tesseract_timeout_seconds" {
  description = "Timeout interno do servico Tesseract OCR."
  type        = number
  default     = 45
}

variable "max_body_bytes" {
  description = "Tamanho maximo do corpo aceito pelo servico OCR."
  type        = number
  default     = 12582912
}

variable "api_replicas" {
  description = "Quantidade de replicas da API."
  type        = number
  default     = 1
}

variable "tesseract_replicas" {
  description = "Quantidade de replicas do Tesseract OCR."
  type        = number
  default     = 1
}
