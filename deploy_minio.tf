resource "null_resource" "deploy_minio" {
  depends_on = [null_resource.create_k8s_secrets, null_resource.k3d_cluster]
  provisioner "local-exec" {
    environment = {
      KUBECONFIG = "${path.module}/.k3d_kubeconfig"
      MODULE_DIR  = "${path.module}"
    }
    command     = "bash ${path.module}/scripts/deploy_minio.sh"
    interpreter = ["/bin/bash", "-c"]
  }
  triggers = {
    deploy_marker = timestamp()
  }
}
