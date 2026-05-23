domain_name           = ""
cloudflare_api_token  = ""
cloudflare_account_id = ""
cloudflare_zone_id    = ""

tesseract_api_build_context = null
tesseract_ocr_build_context = "/home/beto/Documentos/apphouse/resigne-backend/tesseract-ocr-service"

tesseract_api_image = "tesseract-api:latest"
tesseract_ocr_image = "tesseract-ocr:latest"

# API depende de imagem base privada registry.facilitalabs.com.br e nao builda sem docker login.
tesseract_api_replicas   = 0
tesseract_enable_ingress = false
