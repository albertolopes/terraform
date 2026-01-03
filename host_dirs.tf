resource "null_resource" "create_host_dirs" {
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command = <<EOT
set -euo pipefail
mkdir -p ${path.module}/volume/postgres/data || true
mkdir -p ${path.module}/volume/minio || true
mkdir -p ${path.module}/volume/nginx || true
# set permissive permissions on the directories we created (non-recursive) so k3d can mount them
chmod 0777 ${path.module}/volume/postgres || true
chmod 0777 ${path.module}/volume/postgres/data || true
chmod 0777 ${path.module}/volume/minio || true
chmod 0777 ${path.module}/volume/nginx || true
EOT
  }
  triggers = {
    cluster_cfg_md5 = filemd5("${path.module}/cluster.yaml")
  }
}
