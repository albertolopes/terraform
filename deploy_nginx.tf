# deploy nginx deployment + service
resource "null_resource" "deploy_nginx" {
  depends_on = [null_resource.k3d_cluster, null_resource.pull_nginx]

  provisioner "local-exec" {
    environment = {
      KUBECONFIG  = "${path.module}/.k3d_kubeconfig"
    }

    # Apply the nginx manifest directly so the declared replica count in k8s/nginx/nginx.yaml is authoritative
    command = "kubectl --kubeconfig ${path.module}/.k3d_kubeconfig apply -f ${path.module}/k8s/nginx/nginx.yaml"
    interpreter = ["/bin/bash", "-c"]
  }

  triggers = {
    nginx_image   = var.nginx_image
  }
}
