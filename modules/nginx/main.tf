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

        # Keycloak Proxy
        server {
          listen 80;
          server_name keycloak.${var.domain_name};

          location / {
            proxy_pass http://keycloak:8080;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto https;
            proxy_set_header X-Forwarded-Host $host;

            proxy_redirect http://keycloak:8080/ /;
            proxy_redirect http://$host/ /;
          }
        }

        # Minio API Proxy (S3)
        server {
          listen 80;
          server_name minio.${var.domain_name};

          location / {
            proxy_pass http://minio:9000;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto https;
            proxy_set_header X-Forwarded-Host $host;

            proxy_redirect http://minio:9000/ /;
            proxy_redirect http://$host/ /;
          }
        }

        # Minio Console Proxy (Web UI)
        server {
          listen 80;
          server_name minio-console.${var.domain_name};

          location / {
            proxy_pass http://minio-console:9001;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto https;
            proxy_set_header X-Forwarded-Host $host;

            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";

            proxy_redirect http://minio-console:9001/ /;
            proxy_redirect http://$host/ /;
          }
        }

        # API Customizada Proxy
        server {
          listen 80;
          server_name api.${var.domain_name};

          location / {
            proxy_pass http://na-palma-da-mao-api:8080;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto https;
            proxy_set_header X-Forwarded-Host $host;
          }
        }

        # Nginx (Default / Root)
        server {
          listen 80;
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
  }
}