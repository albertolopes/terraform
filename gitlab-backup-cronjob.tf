resource "kubernetes_service_account_v1" "gitlab_backup" {
  metadata {
    name      = "gitlab-backup"
    namespace = kubernetes_namespace_v1.gitlab.metadata[0].name
  }
}

resource "kubernetes_role_v1" "gitlab_backup" {
  metadata {
    name      = "gitlab-backup"
    namespace = kubernetes_namespace_v1.gitlab.metadata[0].name
  }

  rule {
    api_groups = [""]
    resources  = ["pods"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = [""]
    resources  = ["pods/exec"]
    verbs      = ["create", "get"]
  }
}

resource "kubernetes_role_binding_v1" "gitlab_backup" {
  metadata {
    name      = "gitlab-backup"
    namespace = kubernetes_namespace_v1.gitlab.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.gitlab_backup.metadata[0].name
    namespace = kubernetes_namespace_v1.gitlab.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.gitlab_backup.metadata[0].name
  }
}

resource "null_resource" "gitlab_backup_hostpath_preflight" {
  triggers = {
    host_path    = var.gitlab_backup_host_path
    cluster_name = var.k3d_cluster_name
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail

      if ! command -v docker >/dev/null 2>&1; then
        echo "Docker not found; skipping k3d hostPath preflight."
        exit 0
      fi

      NODES="$(docker ps --format '{{.Names}}' | grep -E '^k3d-${var.k3d_cluster_name}-(server|agent)-[0-9]+$' || true)"
      if [ -z "$NODES" ]; then
        echo "No local k3d nodes for cluster ${var.k3d_cluster_name}; skipping k3d hostPath preflight."
        exit 0
      fi

      for node in $NODES; do
        if ! docker inspect "$node" --format '{{range .Mounts}}{{println .Destination}}{{end}}' | grep -qx "${var.backup_mount_point}"; then
          echo "Node $node does not have ${var.backup_mount_point} mounted." >&2
          echo "Do not apply GitLab backup CronJobs until ${var.backup_mount_point} is bind-mounted into every k3d node." >&2
          echo "Current mounts for $node:" >&2
          docker inspect "$node" --format '{{range .Mounts}}{{println .Source "->" .Destination}}{{end}}' >&2
          exit 1
        fi
      done
    EOT
  }

  depends_on = [null_resource.backup_disk]
}

resource "kubernetes_cron_job_v1" "gitlab_backup" {
  metadata {
    name      = "gitlab-backup"
    namespace = kubernetes_namespace_v1.gitlab.metadata[0].name
  }

  spec {
    schedule                      = var.gitlab_backup_schedule
    concurrency_policy            = "Forbid"
    failed_jobs_history_limit     = 3
    successful_jobs_history_limit = 3

    job_template {
      metadata {
        labels = {
          app = "gitlab-backup"
        }
      }

      spec {
        backoff_limit = 1

        template {
          metadata {
            labels = {
              app = "gitlab-backup"
            }
          }

          spec {
            service_account_name = kubernetes_service_account_v1.gitlab_backup.metadata[0].name
            restart_policy       = "OnFailure"

            security_context {
              run_as_user  = 0
              run_as_group = 0
            }

            container {
              name              = "gitlab-backup"
              image             = var.gitlab_backup_kubectl_image
              image_pull_policy = "IfNotPresent"
              command           = ["/bin/sh", "-c"]
              args = [<<-SCRIPT
                set -eu

                NAMESPACE="${kubernetes_namespace_v1.gitlab.metadata[0].name}"
                SELECTOR="${var.gitlab_toolbox_label_selector}"
                DEST_DIR="${var.gitlab_backup_container_mount_path}"

                mkdir -p "$DEST_DIR"

                TOOLBOX_POD="$(kubectl get pods -n "$NAMESPACE" -l "$SELECTOR" --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')"
                if [ -z "$TOOLBOX_POD" ]; then
                  echo "No running gitlab-toolbox pod found with selector: $SELECTOR" >&2
                  exit 1
                fi

                echo "Using toolbox pod: $TOOLBOX_POD"
                kubectl exec -n "$NAMESPACE" "$TOOLBOX_POD" -c toolbox -- /bin/bash -lc 'gitlab-backup create'

                LATEST_BACKUP="$(kubectl exec -n "$NAMESPACE" "$TOOLBOX_POD" -c toolbox -- /bin/bash -lc 'ls -1t /srv/gitlab/tmp/backups/*_gitlab_backup.tar 2>/dev/null | head -n 1')"
                if [ -z "$LATEST_BACKUP" ]; then
                  echo "No GitLab backup tar found in /srv/gitlab/tmp/backups inside $TOOLBOX_POD" >&2
                  exit 1
                fi

                BACKUP_FILE="$(basename "$LATEST_BACKUP")"
                TMP_FILE="$DEST_DIR/$BACKUP_FILE.tmp"
                FINAL_FILE="$DEST_DIR/$BACKUP_FILE"

                echo "Copying $LATEST_BACKUP to $FINAL_FILE"
                kubectl cp -n "$NAMESPACE" -c toolbox "$TOOLBOX_POD:$LATEST_BACKUP" "$TMP_FILE"
                mv "$TMP_FILE" "$FINAL_FILE"
                chmod 0640 "$FINAL_FILE"

                echo "Backup copied to $FINAL_FILE"
              SCRIPT
              ]

              volume_mount {
                name       = "gitlab-backup-hostpath"
                mount_path = var.gitlab_backup_container_mount_path
              }
            }

            volume {
              name = "gitlab-backup-hostpath"

              host_path {
                path = var.gitlab_backup_host_path
                type = "Directory"
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    null_resource.backup_disk,
    null_resource.gitlab_backup_hostpath_preflight,
    module.gitlab,
    kubernetes_role_binding_v1.gitlab_backup
  ]
}

resource "kubernetes_cron_job_v1" "gitlab_backup_cleanup" {
  metadata {
    name      = "gitlab-backup-cleanup"
    namespace = kubernetes_namespace_v1.gitlab.metadata[0].name
  }

  spec {
    schedule                      = var.gitlab_backup_cleanup_schedule
    concurrency_policy            = "Forbid"
    failed_jobs_history_limit     = 1
    successful_jobs_history_limit = 3

    job_template {
      metadata {
        labels = {
          app = "gitlab-backup-cleanup"
        }
      }

      spec {
        backoff_limit = 1

        template {
          metadata {
            labels = {
              app = "gitlab-backup-cleanup"
            }
          }

          spec {
            restart_policy = "OnFailure"

            security_context {
              run_as_user  = 0
              run_as_group = 0
            }

            container {
              name              = "cleanup"
              image             = "busybox:1.36"
              image_pull_policy = "IfNotPresent"
              command           = ["/bin/sh", "-c"]
              args              = ["find ${var.gitlab_backup_container_mount_path} -maxdepth 1 -type f -name '*_gitlab_backup.tar' -mtime +${var.gitlab_backup_retention_days} -print -delete"]

              volume_mount {
                name       = "gitlab-backup-hostpath"
                mount_path = var.gitlab_backup_container_mount_path
              }
            }

            volume {
              name = "gitlab-backup-hostpath"

              host_path {
                path = var.gitlab_backup_host_path
                type = "Directory"
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    null_resource.backup_disk,
    null_resource.gitlab_backup_hostpath_preflight
  ]
}
