resource "null_resource" "create_k8s_secrets" {
  depends_on = [null_resource.k3d_cluster, null_resource.install_ingress]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command = <<EOT
      echo "Simplified secrets management"
      echo "Credentials for Minio, Postgres, Keycloak and other services are now stored directly"
      echo "inside their respective Kubernetes manifest files under \`k8s/<service>/\`."
      echo "This avoids fragile local-exec scripts during \`terraform apply\` and makes the repo"
      echo "easier to reason about and reproduce."
      echo ""
      echo "Guidelines:"
      echo "- Put service secrets in the service's YAML using a Secret manifest, e.g. k8s/postgres/postgres-secret.yaml"
      echo "- Keep sensitive values out of source control in real deployments; for local dev you may include defaults."
      echo "- If you want Terraform to create secrets, add a focused, minimal \`kubectl apply\` step or use the Kubernetes provider."
    EOT
  }
}

# Create secrets using kubectl apply (idempotent, won't fail if already present).
resource "null_resource" "k8s_secret_minio" {
  depends_on = [null_resource.k3d_cluster]
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command = <<EOT
kubectl --kubeconfig "${path.module}/.k3d_kubeconfig" -n default apply -f - <<YAML
apiVersion: v1
kind: Secret
metadata:
  name: minio-credentials
  namespace: default
stringData:
  accesskey: "minioadmin"
  secretkey: "minioadmin"
YAML
EOT
  }
}

resource "null_resource" "k8s_secret_postgres" {
  depends_on = [null_resource.k3d_cluster]
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command = <<EOT
kubectl --kubeconfig "${path.module}/.k3d_kubeconfig" -n default apply -f - <<YAML
apiVersion: v1
kind: Secret
metadata:
  name: postgres-credentials
  namespace: default
stringData:
  POSTGRES_USER: "postgres"
  POSTGRES_PASSWORD: "postgres"
YAML
EOT
  }
}

resource "null_resource" "k8s_secret_keycloak_db" {
  depends_on = [null_resource.k3d_cluster]
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command = <<EOT
kubectl --kubeconfig "${path.module}/.k3d_kubeconfig" -n default apply -f - <<YAML
apiVersion: v1
kind: Secret
metadata:
  name: keycloak-db-credentials
  namespace: default
stringData:
  KC_DB_USERNAME: "keycloak"
  KC_DB_PASSWORD: "keycloak"
YAML
EOT
  }
}

resource "null_resource" "k8s_secret_keycloak_admin" {
  depends_on = [null_resource.k3d_cluster]
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command = <<EOT
kubectl --kubeconfig "${path.module}/.k3d_kubeconfig" -n default apply -f - <<YAML
apiVersion: v1
kind: Secret
metadata:
  name: keycloak-admin
  namespace: default
stringData:
  KEYCLOAK_ADMIN: "admin"
  KEYCLOAK_ADMIN_PASSWORD: "123456"
YAML
EOT
  }
}

resource "null_resource" "create_k8s_secrets_placeholder" {
  depends_on = [null_resource.k3d_cluster, null_resource.install_ingress, null_resource.k8s_secret_minio, null_resource.k8s_secret_postgres, null_resource.k8s_secret_keycloak_db, null_resource.k8s_secret_keycloak_admin]
  # lightweight placeholder so other null_resources can depend on secrets being declared
}
