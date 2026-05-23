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

variable "api_build_context" {
  description = "Diretorio com o Dockerfile da API para build/import local no k3d. Use null para nao buildar."
  type        = string
  default     = null
}

variable "api_dockerfile" {
  description = "Dockerfile usado para build da API. Use null para usar o Dockerfile do contexto."
  type        = string
  default     = null
}

variable "ocr_build_context" {
  description = "Diretorio com o Dockerfile do OCR para build/import local no k3d. Use null para nao buildar."
  type        = string
  default     = null
}

variable "ocr_dockerfile" {
  description = "Dockerfile usado para build do OCR. Use null para usar o Dockerfile do contexto."
  type        = string
  default     = null
}

variable "ocr_tessdata_repo" {
  description = "Repositorio oficial de modelos Tesseract usado no build. Use tessdata_best para qualidade ou tessdata_fast para performance."
  type        = string
  default     = "tessdata_best"
}

variable "ocr_rebuild_token" {
  description = "Token usado para forcar rebuild/import da imagem OCR quando arquivos fonte mudam."
  type        = string
  default     = ""
}

variable "k3d_cluster_name" {
  description = "Nome do cluster k3d usado para importar imagens locais."
  type        = string
  default     = "mycluster"
}

variable "enable_ingress" {
  description = "Habilita Certificate/Ingress publico para a API."
  type        = bool
  default     = true
}
