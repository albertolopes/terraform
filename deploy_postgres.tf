resource "null_resource" "cleanup_postgres_pv" {
  count = var.enable_cleanup ? 1 : 0

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command = "bash ${path.module}/scripts/cleanup_postgres.sh ${path.module}/.k3d_kubeconfig"
  }
  triggers = { ts = timestamp() }
}

resource "null_resource" "deploy_postgres" {
  depends_on = [null_resource.k3d_cluster, null_resource.create_host_dirs, null_resource.create_k8s_secrets]

  provisioner "local-exec" {
    environment = {
      KUBECONFIG = "${path.module}/.k3d_kubeconfig"
      POSTGRES_IMAGE = var.postgres_image
      POSTGRES_HOST_PATH = (length(var.postgres_host_path) > 0 ? var.postgres_host_path : "${path.module}/volume/postgres/data/pgdata")
      USE_LOCAL_PATH = tostring(var.use_local_path)
      MODULE_DIR = "${path.module}"
    }
    command = "bash ${path.module}/scripts/deploy_postgres.sh"
    interpreter = ["/bin/bash", "-c"]
  }

  triggers = {
    postgres_image    = try(filemd5("${path.module}/k8s/postgres/postgres.yaml"), var.postgres_image)
    postgres_hostpath = var.postgres_host_path
    use_local_path    = tostring(var.use_local_path)
    host_dirs_md5     = filemd5("${path.module}/cluster.yaml")
  }
}

resource "null_resource" "deploy_keycloak" {
  depends_on = [null_resource.k3d_cluster, null_resource.deploy_postgres, null_resource.install_ingress, null_resource.create_k8s_secrets]

  provisioner "local-exec" {
    environment = {
      KUBECONFIG = "${path.module}/.k3d_kubeconfig"
      MODULE_DIR  = "${path.module}"
    }
    command     = "bash ${path.module}/scripts/deploy_keycloak.sh"
    interpreter = ["/bin/bash", "-c"]
  }
  triggers = {
    keycloak_image = filemd5("./docker/keycloak.yaml")
  }
}

resource "null_resource" "create_keycloak_role" {
  depends_on = [null_resource.deploy_postgres, null_resource.create_k8s_secrets_placeholder]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command = <<EOT
set -euo pipefail
KUBECONFIG="${path.module}/.k3d_kubeconfig"
# wait for postgres pod ready
echo "Waiting for postgres pod to be ready (timeout 300s)..."
kubectl --kubeconfig "$KUBECONFIG" -n default wait --for=condition=ready pod -l app=postgres --timeout=300s || true

POD=$(kubectl --kubeconfig "$KUBECONFIG" -n default get pods -l app=postgres -o jsonpath='{.items[0].metadata.name}')
if [ -z "$POD" ]; then
  echo "No postgres pod found" >&2
  exit 1
fi

echo "Using postgres pod $POD to ensure role and database for keycloak"

# decode secret values locally (safe) so we don't risk quoting problems when composing SQL
KC_USER=$(kubectl --kubeconfig "$KUBECONFIG" -n default get secret keycloak-db-credentials -o jsonpath='{.data.KC_DB_USERNAME}' | base64 --decode || true)
KC_PASS=$(kubectl --kubeconfig "$KUBECONFIG" -n default get secret keycloak-db-credentials -o jsonpath='{.data.KC_DB_PASSWORD}' | base64 --decode || true)
if [ -z "$KC_USER" ] || [ -z "$KC_PASS" ]; then
  echo "Keycloak DB credentials missing in secret keycloak-db-credentials" >&2
  exit 1
fi

# check if role exists
if kubectl --kubeconfig "$KUBECONFIG" -n default exec "$POD" -- bash -c "psql -U postgres -tAc \"SELECT 1 FROM pg_roles WHERE rolname='"$KC_USER"'\"" | grep -q 1; then
  echo "Role '$KC_USER' already exists"
else
  echo "Creating role '$KC_USER'"
  kubectl --kubeconfig "$KUBECONFIG" -n default exec "$POD" -- bash -c "psql -U postgres -c \"CREATE ROLE \"\"$KC_USER\"\" WITH LOGIN PASSWORD '$KC_PASS';\""
fi

# check/create database
if kubectl --kubeconfig "$KUBECONFIG" -n default exec "$POD" -- bash -c "psql -U postgres -tAc \"SELECT 1 FROM pg_database WHERE datname='keycloak'\"" | grep -q 1; then
  echo "Database 'keycloak' already exists"
else
  echo "Creating database 'keycloak' owned by $KC_USER"
  kubectl --kubeconfig "$KUBECONFIG" -n default exec "$POD" -- bash -c "psql -U postgres -c \"CREATE DATABASE keycloak OWNER \"\"$KC_USER\"\";\""
fi

# trigger keycloak deployment rollout to pick changes
kubectl --kubeconfig "$KUBECONFIG" -n default rollout restart deployment/keycloak || true
EOT
  }

  triggers = {
    ts = timestamp()
  }
}
