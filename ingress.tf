# install ingress-nginx controller and create Ingress
resource "null_resource" "install_ingress" {
  depends_on = [null_resource.k3d_cluster, null_resource.create_host_dirs]

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
  depends_on = [null_resource.k3d_cluster, null_resource.create_host_dirs]
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command = <<EOT
set -euo pipefail
KUBECONFIG="${path.module}/.k3d_kubeconfig"
# Attempt to remove common traefik resources
kubectl --kubeconfig "$KUBECONFIG" -n kube-system delete deployment,service,daemonset -l app=traefik --ignore-not-found=true || true
kubectl --kubeconfig "$KUBECONFIG" -n kube-system delete svc traefik --ignore-not-found=true || true
kubectl --kubeconfig "$KUBECONFIG" -n kube-system delete pods -l app=svclb-traefik --ignore-not-found=true || true
EOT
  }
  triggers = { ts = timestamp() }
}
