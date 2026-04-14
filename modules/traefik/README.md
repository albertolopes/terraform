Todos os targets úteis do módulo Traefik

# Namespace
terraform apply -target=module.traefik.kubernetes_namespace_v1.traefik

# Service Account
terraform apply -target=module.traefik.kubernetes_service_account_v1.traefik

# ClusterRole
terraform apply -target=module.traefik.kubernetes_cluster_role_v1.traefik

# ClusterRoleBinding
terraform apply -target=module.traefik.kubernetes_cluster_role_binding_v1.traefik

# ConfigMap
terraform apply -target=module.traefik.kubernetes_config_map_v1.traefik

# CRDs (null_resource)
terraform apply -target=module.traefik.null_resource.traefik_crds

# Deployment
terraform apply -target=module.traefik.kubernetes_deployment_v1.traefik

# IngressClass
terraform apply -target=module.traefik.kubernetes_ingress_class_v1.traefik

# Service LoadBalancer
terraform apply -target=module.traefik.kubernetes_service_v1.traefik

# Secret do Dashboard
terraform apply -target=module.traefik.kubernetes_secret_v1.dashboard_auth

# Middleware de Auth
terraform apply -target=module.traefik.kubernetes_manifest.dashboard_auth

# IngressRoute do Dashboard
terraform apply -target='module.traefik.kubernetes_manifest.traefik_dashboard[0]'