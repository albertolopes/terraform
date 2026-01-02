output "kubeconfig_path" {
  description = "Path to the kubeconfig file generated for the k3d cluster"
  value       = fileexists("${path.module}/.k3d_kubeconfig") ? "${path.module}/.k3d_kubeconfig" : ""
}

output "nginx_node_port" {
  description = "NodePort where nginx service is exposed on the cluster nodes (static configured in manifest)"
  value       = 30080
}

output "nginx_cluster_ip" {
  description = "Cluster IP of the nginx service is not known until kubectl applies; check the kubeconfig and kubectl get svc"
  value       = ""
}
