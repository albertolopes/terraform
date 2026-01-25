# Port-forward helper resource
resource "null_resource" "port_forward" {
  depends_on = [kubernetes_service_v1.nginx]

  provisioner "local-exec" {
    environment = {
      MODULE_DIR = "${path.module}"
      KUBECONFIG  = "${path.module}/.k3d_kubeconfig"
    }

    command = "bash ${path.module}/scripts/port_forward.sh"
    interpreter = ["/bin/bash", "-c"]
  }

  # ensure port-forward is removed on destroy
  provisioner "local-exec" {
    when    = destroy
    environment = {
      MODULE_DIR = "${path.module}"
    }
    command = "bash ${path.module}/scripts/stop_port_forward.sh"
    interpreter = ["/bin/bash", "-c"]
  }
}
