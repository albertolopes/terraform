variable "domain_name" {
  description = "Base domain name"
  type        = string
}

# --- Secret nginx-certs (Removido, agora gerenciado pelo Cert-Manager) ---
# O segredo 'nginx-certs' agora é criado pelo recurso 'kubernetes_manifest.avocado_cert' 
# no módulo de networking para usar certificados reais da Let's Encrypt.

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
          listen 443 ssl;
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

        # Minio API Proxy (S3)
        server {
          listen 80;
          listen 443 ssl;
          server_name minio.${var.domain_name};

          location / {
            proxy_pass http://minio:9000;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Forwarded-Host $host;

            # Redirecionamentos para Minio API
            proxy_redirect http://$host/ /;
            proxy_redirect http://minio:9000/ /;
            proxy_redirect http://minio.${var.domain_name}/ /;
          }
        }

        # Minio Console Proxy (Web UI)
        server {
          listen 80;
          listen 443 ssl;
          server_name minio-console.${var.domain_name};

          location / {
            # Aponta para o novo serviço 'minio-console' que criamos manualmente
            proxy_pass http://minio-console:9001;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Forwarded-Host $host;

            # Necessário para WebSockets (Minio Console usa)
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";

            # Redirecionamentos para Minio Console
            proxy_redirect http://$host/ /;
            proxy_redirect http://minio-console:9001/ /;
            proxy_redirect http://minio-console.${var.domain_name}/ /;
          }
        }

        # API Customizada Proxy
        server {
          listen 80;
          listen 443 ssl;
          server_name api.${var.domain_name};

          location / {
            proxy_pass http://na-palma-da-mao-api:8080;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Forwarded-Host $host;
          }
        }

        # Nginx (Default / Root)
        server {
          listen 80;
          listen 443 ssl;
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
            secret_name = "nginx-certs" # Geranciado pelo Cert-Manager no módulo de networking
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
