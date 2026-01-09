# install ingress-nginx controller and create Ingress
resource "null_resource" "install_ingress" {
  depends_on = [null_resource.k3d_cluster, null_resource.remove_traefik]

  provisioner "local-exec" {
    environment = {
      MODULE_DIR = "${path.module}"
      KUBECONFIG  = "${path.module}/.k3d_kubeconfig"
    }

    command = "bash ${path.module}/scripts/install_ingress.sh"
    interpreter = ["/bin/bash", "-c"]
  }

  triggers = {
    ingress_marker = timestamp()
  }
}

# Ensure Traefik is removed if present (idempotent)
resource "null_resource" "remove_traefik" {
  depends_on = [null_resource.k3d_cluster]
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command = <<EOT
set -euo pipefail
KUBECONFIG="${path.module}/.k3d_kubeconfig"
NS=kube-system
# try helm uninstall first
if command -v helm >/dev/null 2>&1; then
  helm -n $NS uninstall traefik --wait --timeout 30s || true
fi
# delete common traefik resources by label/name
kubectl --kubeconfig "$KUBECONFIG" -n $NS delete deployment,service,daemonset,replicaset,job,cronjob -l app=traefik --ignore-not-found=true || true
kubectl --kubeconfig "$KUBECONFIG" -n $NS delete deployment traefik --ignore-not-found=true || true
kubectl --kubeconfig "$KUBECONFIG" -n $NS delete svc traefik --ignore-not-found=true || true
# delete any helm-install-traefik or traefik pods
kubectl --kubeconfig "$KUBECONFIG" -n $NS get pods -o name 2>/dev/null | grep -Ei 'traefik|helm-install-traefik' | xargs -r -n1 kubectl --kubeconfig "$KUBECONFIG" -n $NS delete --ignore-not-found=true || true
# delete any svclb daemonsets/pods referencing traefik
kubectl --kubeconfig "$KUBECONFIG" -n $NS get daemonset -o name 2>/dev/null | grep -i svclb || true | xargs -r -n1 kubectl --kubeconfig "$KUBECONFIG" -n $NS delete --ignore-not-found=true || true
kubectl --kubeconfig "$KUBECONFIG" -n $NS get pods -o name 2>/dev/null | grep -i svclb || true | xargs -r -n1 kubectl --kubeconfig "$KUBECONFIG" -n $NS delete --ignore-not-found=true || true

# quick wait loop (max 60s) for any traefik/helm-install pods to disappear
for i in {1..12}; do
  sleep 5
  if ! kubectl --kubeconfig "$KUBECONFIG" -n $NS get pods -o name 2>/dev/null | grep -Ei 'traefik|helm-install-traefik|svclb-traefik' >/dev/null 2>&1; then
    echo "Traefik artifacts removed"
    break
  fi
  echo "Waiting for Traefik artifacts to be removed... ($((i*5))s)"
done
EOT
  }
  triggers = { ts = timestamp() }
}
