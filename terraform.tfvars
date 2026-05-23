domain_name           = ""
cloudflare_api_token  = ""
cloudflare_account_id = ""
cloudflare_zone_id    = ""

tesseract_api_build_context = "/home/beto/Documentos/apphouse/resigne-backend"
tesseract_api_dockerfile    = "/home/beto/Documentos/aaa-pessoal/terraform/docker/tesseract-api.Dockerfile"
tesseract_ocr_build_context = "/home/beto/Documentos/apphouse/resigne-backend/tesseract-ocr-service"

tesseract_api_image = "tesseract-api:latest"
tesseract_ocr_image = "tesseract-ocr:latest"

tesseract_api_replicas   = 1
tesseract_enable_ingress = true
