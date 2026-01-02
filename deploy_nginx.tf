# deploy nginx deployment + service
resource "null_resource" "deploy_nginx" {
  depends_on = [null_resource.k3d_cluster, null_resource.pull_nginx]

  provisioner "local-exec" {
    environment = {
      KUBECONFIG  = "${path.module}/.k3d_kubeconfig"
    }

    # Run the deployment script which creates ConfigMaps, secrets and Deployment/Service
    command = "bash ${path.module}/scripts/deploy_nginx.sh"
    interpreter = ["/bin/bash", "-c"]
  }

  triggers = {
    deploy_marker = timestamp()
  }
}
