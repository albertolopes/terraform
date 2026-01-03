resource "null_resource" "cleanup_postgres_pv" {
  count = var.enable_cleanup ? 1 : 0

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command = "bash ${path.module}/scripts/cleanup_postgres.sh ${path.module}/.k3d_kubeconfig"
  }
  triggers = { ts = timestamp() }
}

resource "null_resource" "deploy_postgres" {
  depends_on = [null_resource.k3d_cluster, null_resource.create_host_dirs]

  provisioner "local-exec" {
    environment = {
      KUBECONFIG = "${path.module}/.k3d_kubeconfig"
      POSTGRES_IMAGE = var.postgres_image
      POSTGRES_HOST_PATH = (length(var.postgres_host_path) > 0 ? var.postgres_host_path : "${path.module}/volume/postgres/data/pgdata")
      USE_LOCAL_PATH = tostring(var.use_local_path)
      MODULE_DIR = "${path.module}"
    }
    command = "bash ${path.module}/scripts/deploy_postgres.sh"
    interpreter = ["/bin/bash", "-c"]
  }

  triggers = {
    postgres_image    = try(filemd5("${path.module}/k8s/postgres/postgres.yaml"), var.postgres_image)
    postgres_hostpath = var.postgres_host_path
    use_local_path    = tostring(var.use_local_path)
    host_dirs_md5     = filemd5("${path.module}/cluster.yaml")
  }
}

resource "null_resource" "deploy_keycloak" {
  depends_on = [null_resource.k3d_cluster, null_resource.deploy_postgres, null_resource.install_ingress]

  provisioner "local-exec" {
    environment = {
      KUBECONFIG = "${path.module}/.k3d_kubeconfig"
      MODULE_DIR  = "${path.module}"
    }
    command     = "bash ${path.module}/scripts/deploy_keycloak.sh"
    interpreter = ["/bin/bash", "-c"]
  }
  triggers = {
    keycloak_image = filemd5("./docker/keycloak.yaml")
  }
}
