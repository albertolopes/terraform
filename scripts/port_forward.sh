#!/usr/bin/env bash
set -euo pipefail
KUBECONFIG=${KUBECONFIG:-$PWD/.k3d_kubeconfig}
MODULE_DIR=${MODULE_DIR:-$PWD}

# check if localhost:30080 is already listening
if ss -lnt | grep -q ':30080\b'; then
  echo "localhost:30080 already listening"
  exit 0
fi
# try connecting to loadbalancer container mapping
if docker ps --format '{{.Names}} {{.Ports}}' | grep -q 'k3d-mycluster-serverlb.*30080'; then
  echo "Loadbalancer publishes 30080 on host, no port-forward needed"
  exit 0
fi
# start kubectl port-forward in background and write pid
PIDFILE="$MODULE_DIR/.k3d_port_forward.pid"
# if existing pidfile, ensure process not running
if [ -f "$PIDFILE" ]; then
  OLDPID=$(cat "$PIDFILE") || true
  if [ -n "$OLDPID" ] && kill -0 "$OLDPID" 2>/dev/null; then
    echo "port-forward already running with PID $OLDPID"
    exit 0
  else
    rm -f "$PIDFILE"
  fi
fi
# run port-forward in background
nohup kubectl --kubeconfig "$KUBECONFIG" port-forward svc/nginx-service 30080:80 >/dev/null 2>&1 &
PF_PID=$!
echo $PF_PID > "$PIDFILE"
echo "Started kubectl port-forward with PID $PF_PID"

