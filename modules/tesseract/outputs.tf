output "namespace" {
  description = "Namespace Kubernetes do Tesseract."
  value       = kubernetes_namespace_v1.tesseract.metadata[0].name
}

output "api_service_name" {
  description = "Nome do Service da API Tesseract."
  value       = kubernetes_service_v1.api.metadata[0].name
}

output "tesseract_ocr_service_name" {
  description = "Nome do Service interno do Tesseract OCR."
  value       = kubernetes_service_v1.tesseract_ocr.metadata[0].name
}

output "api_url" {
  description = "URL publica da API Tesseract."
  value       = "https://${local.public_host}"
}
