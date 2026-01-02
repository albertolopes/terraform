# install ingress-nginx controller and create Ingress
resource "null_resource" "install_ingress" {
  depends_on = [null_resource.k3d_cluster, null_resource.deploy_nginx]

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
