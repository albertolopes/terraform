resource "null_resource" "backup_disk" {
  triggers = {
    device      = var.backup_device
    mount_point = var.backup_mount_point
    directories = sha256(jsonencode(var.backup_directories))
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail

      DEVICE="${var.backup_device}"
      MOUNT_POINT="${var.backup_mount_point}"
      DIRS='${jsonencode(var.backup_directories)}'

      case "$DEVICE" in
        /dev/sda|/dev/sda*|/dev/sdb|/dev/sdb*)
          echo "Refusing to touch protected device $DEVICE" >&2
          exit 1
          ;;
      esac

      if [ ! -b "$DEVICE" ]; then
        echo "Backup device $DEVICE does not exist or is not a block device" >&2
        exit 1
      fi

      CURRENT_MOUNT="$(findmnt -rn -S "$DEVICE" -o TARGET 2>/dev/null | head -n 1 || true)"
      if [ -n "$CURRENT_MOUNT" ] && [ "$CURRENT_MOUNT" != "$MOUNT_POINT" ]; then
        echo "$DEVICE is already mounted at $CURRENT_MOUNT; refusing to remount it at $MOUNT_POINT" >&2
        exit 1
      fi

      FSTYPE="$(sudo blkid -o value -s TYPE "$DEVICE" 2>/dev/null || true)"
      if [ -z "$FSTYPE" ]; then
        SIGNATURES="$(sudo wipefs -n "$DEVICE" 2>/dev/null | tail -n +2 || true)"
        if [ -n "$SIGNATURES" ]; then
          echo "$DEVICE has existing signatures but blkid did not identify a filesystem. Review manually before formatting." >&2
          echo "$SIGNATURES" >&2
          exit 1
        fi

        echo "No filesystem detected on $DEVICE; creating ext4 filesystem."
        sudo mkfs.ext4 -F "$DEVICE"
        FSTYPE="ext4"
      else
        echo "Existing filesystem detected on $DEVICE: $FSTYPE. It will not be formatted."
      fi

      UUID="$(sudo blkid -o value -s UUID "$DEVICE")"
      if [ -z "$UUID" ]; then
        echo "Could not read UUID from $DEVICE" >&2
        exit 1
      fi

      sudo mkdir -p "$MOUNT_POINT"

      if grep -Eq "^[[:space:]]*UUID=$UUID[[:space:]]+$MOUNT_POINT[[:space:]]" /etc/fstab; then
        echo "fstab already contains UUID=$UUID for $MOUNT_POINT"
      else
        EXISTING_ENTRY="$(awk -v mp="$MOUNT_POINT" '$1 !~ /^#/ && $2 == mp { print }' /etc/fstab || true)"
        if [ -n "$EXISTING_ENTRY" ]; then
          echo "/etc/fstab already has an entry for $MOUNT_POINT that does not use UUID=$UUID:" >&2
          echo "$EXISTING_ENTRY" >&2
          exit 1
        fi

        echo "UUID=$UUID $MOUNT_POINT $FSTYPE defaults,nofail 0 2" | sudo tee -a /etc/fstab >/dev/null
      fi

      if ! mountpoint -q "$MOUNT_POINT"; then
        sudo mount "$MOUNT_POINT"
      fi

      mountpoint -q "$MOUNT_POINT"

      python3 - <<PY | while IFS= read -r dir; do sudo mkdir -p "$dir"; done
import json
for item in json.loads('''$DIRS'''):
    print(item)
PY

      sudo chmod 0775 ${join(" ", var.backup_directories)}
      sudo chown root:root ${join(" ", var.backup_directories)}
    EOT
  }
}
