variable "domain_name" {
  description = "Base domain name"
  type        = string
}

# --- 1. Autoridade Certificadora (CA) Raiz ---
resource "tls_private_key" "ca" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_self_signed_cert" "ca" {
  private_key_pem = tls_private_key.ca.private_key_pem

  subject {
    common_name  = "Avocado Tech Local Root CA"
    organization = "Avocado Tech"
  }

  is_ca_certificate     = true
  validity_period_hours = 87600 # 10 anos

  allowed_uses = [
    "cert_signing",
    "crl_signing",
  ]
}

# Exportar o certificado da CA para o host (para o usuário instalar)
resource "local_file" "ca_cert" {
  content  = tls_self_signed_cert.ca.cert_pem
  filename = "${path.module}/../../avocado-ca.crt"
}

# --- 2. Certificado do Servidor Nginx (Assinado pela CA) ---
resource "tls_private_key" "nginx" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "nginx" {
  private_key_pem = tls_private_key.nginx.private_key_pem

  subject {
    common_name  = "*.${var.domain_name}"
    organization = "Avocado Tech"
  }

  dns_names = [
    var.domain_name,
    "*.${var.domain_name}",
    "nginx.${var.domain_name}",
    "keycloak.${var.domain_name}",
    "minio.${var.domain_name}"
  ]
}

resource "tls_locally_signed_cert" "nginx" {
  cert_request_pem   = tls_cert_request.nginx.cert_request_pem
  ca_private_key_pem = tls_private_key.ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.ca.cert_pem

  validity_period_hours = 8760 # 1 ano

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

# --- 3. Kubernetes Secret ---
resource "kubernetes_secret_v1" "nginx_certs" {
  metadata {
    name      = "nginx-certs"
    namespace = "default"
  }
  type = "kubernetes.io/tls"
  data = {
    "tls.crt" = tls_locally_signed_cert.nginx.cert_pem
    "tls.key" = tls_private_key.nginx.private_key_pem
  }
}

# --- 4. Nginx Configuration ---
resource "kubernetes_config_map_v1" "nginx_config" {
  metadata {
    name      = "nginx-config"
    namespace = "default"
  }
  data = {
    "nginx.conf" = <<-EOT
      user  nginx;
      worker_processes  1;
      error_log  /var/log/nginx/error.log warn;
      pid        /var/run/nginx.pid;

      events {
        worker_connections 1024;
      }

      http {
        include       /etc/nginx/mime.types;
        default_type  application/octet-stream;
        sendfile        on;
        keepalive_timeout  65;

        # Resolver interno do K8s
        resolver 10.43.0.10 valid=30s;

        # Configurações SSL Globais
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_prefer_server_ciphers on;
        ssl_certificate /etc/nginx/certs/tls.crt;
        ssl_certificate_key /etc/nginx/certs/tls.key;

        # Keycloak Proxy
        server {
          listen 80;
          # listen 443 ssl;
          server_name keycloak.${var.domain_name};

          location / {
            proxy_pass http://keycloak:8080;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Forwarded-Host $host;

            # Forçar redirecionamentos serem relativos ao host acessado
            proxy_redirect http://$host/ /;
            proxy_redirect http://keycloak:8080/ /;
            proxy_redirect http://keycloak.${var.domain_name}/ /;
          }
        }

        # Minio Proxy
        server {
          listen 80;
          # listen 443 ssl;
          server_name minio.${var.domain_name};

          location / {
            proxy_pass http://minio:9000;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Forwarded-Host $host;

            # Redirecionamentos para Minio
            proxy_redirect http://$host/ /;
            proxy_redirect http://minio:9000/ /;
            proxy_redirect http://minio.${var.domain_name}/ /;
          }
        }

        # Nginx (Default / Root)
        server {
          listen 80;
          # listen 443 ssl;
          server_name nginx.${var.domain_name} ${var.domain_name} _;

          location / {
            root /usr/share/nginx/html;
            index index.html index.htm;
          }
        }
      }
    EOT
  }
}

resource "kubernetes_config_map_v1" "nginx_html" {
  metadata {
    name      = "nginx-html"
    namespace = "default"
  }
  data = {
    "index.html" = <<-EOT
      <!doctype html>
      <html>
      <head>
        <meta charset="utf-8">
        <title>NGINX (managed by k3d)</title>
      </head>
      <body>
        <h1>NGINX is your Entry Point! 🚀</h1>
        <p>This Nginx instance is now acting as a Reverse Proxy for all services on ${var.domain_name}.</p>
      </body>
      </html>
    EOT
  }
}

resource "kubernetes_deployment_v1" "nginx" {
  metadata {
    name      = "nginx"
    namespace = "default"
  }
  spec {
    replicas = 2
    selector {
      match_labels = {
        app = "nginx"
      }
    }
    template {
      metadata {
        labels = {
          app = "nginx"
        }
        annotations = {
          # Força o reinício dos pods se a configuração mudar
          "checksum/config" = sha256(jsonencode(kubernetes_config_map_v1.nginx_config.data))
        }
      }
      spec {
        security_context {
          fs_group = "101"
        }
        container {
          name  = "nginx"
          image = "nginx:1.29.4-alpine"
          port {
            name           = "http"
            container_port = 80
          }
          port {
            name           = "https"
            container_port = 443
          }
          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "256Mi"
            }
          }
          volume_mount {
            name       = "html-config"
            mount_path = "/usr/share/nginx/html"
          }
          volume_mount {
            name       = "nginx-config"
            mount_path = "/etc/nginx/nginx.conf"
            sub_path   = "nginx.conf"
          }
          volume_mount {
            name       = "nginx-certs"
            mount_path = "/etc/nginx/certs"
            read_only  = true
          }
        }
        volume {
          name = "nginx-config"
          config_map {
            name = kubernetes_config_map_v1.nginx_config.metadata[0].name
          }
        }
        volume {
          name = "html-config"
          config_map {
            name = kubernetes_config_map_v1.nginx_html.metadata[0].name
          }
        }
        volume {
          name = "nginx-certs"
          secret {
            secret_name = kubernetes_secret_v1.nginx_certs.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "nginx" {
  metadata {
    name      = "nginx"
    namespace = "default"
  }
  spec {
    selector = {
      app = "nginx"
    }
    type = "LoadBalancer"
    port {
      name        = "http"
      port        = 80
      target_port = 80
    }
    port {
      name        = "https"
      port        = 443
      target_port = 443
    }
  }
}
