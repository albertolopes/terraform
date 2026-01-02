output "kubeconfig_path" {
  description = "Path to the kubeconfig file generated for the k3d cluster (project-relative). Returns null when not present."
  value       = fileexists("${path.module}/.k3d_kubeconfig") ? "${path.module}/.k3d_kubeconfig" : null
}

output "nginx_node_port" {
  description = "NodePort where nginx service is exposed on the cluster nodes (static configured in manifest)"
  value       = 30080
}

output "nginx_cluster_ip" {
  description = "Cluster (external) IP assigned to the nginx service by the k3d load-balancer; null if not known yet"
  value       = null
}
