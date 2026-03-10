variable "cluster_config_path" {
  description = "Path to the k3d cluster config file"
  type        = string
}

variable "scripts_path" {
  description = "Path to the scripts directory"
  type        = string
}

resource "null_resource" "k3d_cluster" {
  triggers = {
    script_hash       = filemd5("${var.scripts_path}/k3d_create.sh")
    cluster_cfg_hash  = filemd5(var.cluster_config_path)
    # Força recriação se o arquivo de kubeconfig sumir (ex: cluster deletado manualmente)
    kubeconfig_missing = fileexists("${path.cwd}/.k3d_kubeconfig") ? "found" : "missing"
  }

  provisioner "local-exec" {
    command = "bash ${var.scripts_path}/k3d_create.sh"
  }
}

resource "null_resource" "create_host_dirs" {
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command = <<EOT
set -euo pipefail
mkdir -p ${path.cwd}/volume/postgres/data || true
mkdir -p ${path.cwd}/volume/minio || true
mkdir -p ${path.cwd}/volume/nginx || true
chmod 0777 ${path.cwd}/volume/postgres || true
chmod 0777 ${path.cwd}/volume/postgres/data || true
chmod 0777 ${path.cwd}/volume/minio || true
chmod 0777 ${path.cwd}/volume/nginx || true
EOT
  }
  triggers = {
    cluster_cfg_md5 = filemd5(var.cluster_config_path)
  }
}

output "kubeconfig_path" {
  value = "${path.cwd}/.k3d_kubeconfig"
  depends_on = [null_resource.k3d_cluster]
}
