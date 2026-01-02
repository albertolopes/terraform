# k3d cluster creation and kubeconfig export
resource "null_resource" "k3d_cluster" {
  provisioner "local-exec" {
    environment = {
      MODULE_DIR = "${path.module}"
    }

    command = "bash ${path.module}/scripts/k3d_create.sh"
  }

  triggers = {
    kubeconfig_md5 = fileexists("${path.module}/.k3d_kubeconfig") ? filemd5("${path.module}/.k3d_kubeconfig") : timestamp()
  }

  lifecycle {
    create_before_destroy = true
  }
}
