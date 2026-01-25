#!/usr/bin/env bash
set -euo pipefail

MODULE_DIR=${MODULE_DIR:-$PWD}
PID_DIR="$MODULE_DIR/.pids"

if [ -d "$PID_DIR" ]; then
  echo "Stopping all port-forward processes..."
  for pid_file in "$PID_DIR"/*.pid; do
    if [ -f "$pid_file" ]; then
      pid=$(cat "$pid_file")
      if ps -p $pid > /dev/null; then
        echo "Stopping process with PID $pid from file $pid_file..."
        kill $pid
      fi
      rm "$pid_file"
    fi
  done
  # Clean up the directory itself
  rmdir "$PID_DIR" 2>/dev/null || true
  echo "Cleanup complete."
else
  echo "No PID directory found. Nothing to stop."
fi
