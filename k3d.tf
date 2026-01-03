# k3d cluster creation and kubeconfig export
resource "null_resource" "k3d_cluster" {
  provisioner "local-exec" {
    environment = {
      MODULE_DIR     = "${path.module}"
      CLUSTER_CONFIG = "${path.module}/cluster.yaml"
      FORCE_RECREATE = "1"
    }

    command = "bash ${path.module}/scripts/k3d_create.sh"
  }

  # Recreate when cluster configuration changes
  triggers = {
    config_hash = filemd5("${path.module}/cluster.yaml")
  }

  lifecycle {
    create_before_destroy = true
  }

  # ensure host directories exist before creating the cluster
  depends_on = [null_resource.create_host_dirs]
}
