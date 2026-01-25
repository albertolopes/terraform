# k3d cluster creation and kubeconfig export
resource "null_resource" "k3d_cluster" {
  # This trigger ensures the cluster is recreated if the script changes.
  triggers = {
    script_hash = filemd5("${path.module}/scripts/k3d_create.sh")
  }

  provisioner "local-exec" {
    command = "bash ${path.module}/scripts/k3d_create.sh"
  }
}
