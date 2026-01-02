# deploy nginx deployment + service
resource "null_resource" "deploy_nginx" {
  depends_on = [null_resource.k3d_cluster, null_resource.pull_nginx]

  provisioner "local-exec" {
    environment = {
      KUBECONFIG  = "${path.module}/.k3d_kubeconfig"
    }

    # Run the consolidated runner which pre-pulls/imports images and drives the full deploy
    command = "bash ${path.module}/run_deploy.sh"
    interpreter = ["/bin/bash", "-c"]
  }

  triggers = {
    deploy_marker = timestamp()
  }
}
