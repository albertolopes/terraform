# volume/

This directory is intended to hold host-mounted directories used as persistent volumes for local development.

Usage:
- `volume/minio` — intended as host data dir for MinIO when running via docker-compose (maps to `/data`).
- `volume/postgres` — intended as host data dir for Postgres when/if you prefer hostPath mounting.

Notes:
- For k3d/kubernetes it's recommended to use named volumes or the cluster's storageClass (`local-path`) instead of binding arbitrary host paths; hostPath PVs may need special handling.
- These .gitkeep files are placeholders so the empty directories are tracked by git if you choose to add them.

