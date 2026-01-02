resource "null_resource" "deploy_postgres" {
  depends_on = [null_resource.k3d_cluster]

  provisioner "local-exec" {
    environment = {
      KUBECONFIG = "${path.module}/.k3d_kubeconfig"
    }
    command = "bash ${path.module}/scripts/deploy_postgres.sh"
    interpreter = ["/bin/bash", "-c"]
  }

  triggers = {
    postgres_image = try(filemd5("${path.module}/docker/postgres.yaml"), var.postgres_image)
  }
}
