# k3d cluster creation and kubeconfig export
resource "null_resource" "k3d_cluster" {
  provisioner "local-exec" {
    environment = {
      MODULE_DIR = "${path.module}"
    }

    command = "bash ${path.module}/scripts/k3d_create.sh"
  }

  # No triggers - creation is handled by provisioner and lifecycle

  lifecycle {
    create_before_destroy = true
  }
}
