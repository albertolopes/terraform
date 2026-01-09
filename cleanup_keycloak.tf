resource "null_resource" "cleanup_keycloak_jobs" {
  depends_on = [null_resource.deploy_keycloak]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command = <<-EOT
      set -euo pipefail
      KUBECONFIG="${path.module}/.k3d_kubeconfig"

      echo "Waiting up to 300s for Keycloak deployment to have available replicas..."
      kubectl --kubeconfig "$KUBECONFIG" -n default rollout status deployment/keycloak --timeout=300s || true

      AVAILABLE=$(kubectl --kubeconfig "$KUBECONFIG" -n default get deployment keycloak -o jsonpath='{.status.availableReplicas}' 2>/dev/null || echo 0)
      if [ "$AVAILABLE" != "" ] && [ "$AVAILABLE" -ge 1 ]; then
        echo "Keycloak available (availableReplicas=$AVAILABLE). Deleting create-keycloak jobs if present..."
        kubectl --kubeconfig "$KUBECONFIG" -n default delete job create-keycloak-db-flxkq create-keycloak-role-bs4b5 --ignore-not-found || true
        # also delete any jobs prefixed create-keycloak-
        kubectl --kubeconfig "$KUBECONFIG" -n default get jobs -o name | grep create-keycloak- | xargs -r kubectl --kubeconfig "$KUBECONFIG" -n default delete || true
        echo "Cleanup complete."
      else
        echo "Keycloak not available (availableReplicas=$AVAILABLE). Skipping job deletion."
      fi
    EOT
  }

  triggers = {
    keycloak_ready = timestamp()
  }
}

