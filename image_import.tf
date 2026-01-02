# Ensure the nginx image is pulled locally and imported into the k3d cluster before deploying
resource "null_resource" "pull_nginx" {
  provisioner "local-exec" {
    environment = {
      IMAGE = var.nginx_image
    }

    command = "bash ${path.module}/scripts/image_import_wrapper.sh"
    interpreter = ["/bin/bash", "-c"]
  }

  triggers = {
    image = var.nginx_image
  }
}
