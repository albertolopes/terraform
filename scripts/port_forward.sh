#!/usr/bin/env bash
set -euo pipefail

KUBECONFIG=${KUBECONFIG:-$PWD/.k3d_kubeconfig}
MODULE_DIR=${MODULE_DIR:-$PWD}
PID_DIR="$MODULE_DIR/.pids"
mkdir -p "$PID_DIR"

# Function to start port-forward if not already running
start_port_forward() {
  local service_name=$1
  local local_port=$2
  local remote_port=$3
  local pid_file="$PID_DIR/${service_name}.pid"

  # Check if port is already in use
  if lsof -i :$local_port >/dev/null; then
    echo "Port $local_port is already in use. Assuming port-forward is running."
    return
  fi

  # Check for existing PID file
  if [ -f "$pid_file" ] && ps -p $(cat "$pid_file") > /dev/null; then
    echo "Port-forward for $service_name already running with PID $(cat "$pid_file")."
    return
  fi

  echo "Starting port-forward for $service_name on port $local_port..."
  nohup kubectl --kubeconfig "$KUBECONFIG" port-forward "svc/$service_name" "$local_port:$remote_port" >/dev/null 2>&1 &
  local pf_pid=$!
  echo $pf_pid > "$pid_file"
  echo "Started $service_name port-forward with PID $pf_pid."
}

# Start port-forwards
start_port_forward "nginx" 8081 80
start_port_forward "postgres" 5432 5432

echo "Port-forwarding setup complete."
