#!/usr/bin/env bash
set -euo pipefail
MODULE_DIR=${MODULE_DIR:-$PWD}
PIDFILE="$MODULE_DIR/.k3d_port_forward.pid"
if [ -f "$PIDFILE" ]; then
  PID=$(cat "$PIDFILE") || true
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    kill "$PID" || true
    echo "Killed port-forward PID $PID"
  fi
  rm -f "$PIDFILE"
  echo "Removed pidfile $PIDFILE"
else
  echo "No pidfile found at $PIDFILE"
fi

