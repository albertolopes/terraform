k8s/ layout and best practices

Structure
- k8s/
  - ingress/          # host-based ingress rules and ingress-related configmaps
  - nginx/            # nginx app manifests (deployment, service, pv/pvc)
  - minio/            # minio app manifests
  - postgres/         # postgres app manifests

Guidelines
- Each app folder should contain the following canonical files:
  - deployment.yaml (or statefulset.yaml for stateful apps)
  - service-<mode>.yaml (service-loadbalancer.yaml, service-nodeport.yaml, service-clusterip.yaml)
  - pv/pvc if required (pv-hostpath.yaml)
  - optional: hpa.yaml, ingress.yaml (ingress rules live in k8s/ingress/)

- Keep a single canonical ingress per host in `k8s/ingress/`. Remove duplicates under each app folder.
- Avoid using hostPath in production; for dev it's acceptable. Prefer a storageClass and dynamic provisioning for prod.
- Use `resources` and `probes` in all containers.
- For stateful apps (postgres, distributed minio) use StatefulSet and volumeClaimTemplates.

Applying
- Apply manifests idempotently with kubectl apply -f <path> or via your Terraform null_resources that call kubectl.

Examples
- Expose HTTP via Ingress (recommended): create ClusterIP service + Ingress in k8s/ingress/.
- Expose a DB via TCP through ingress-nginx: use `ingress-nginx` TCP ConfigMap (k8s/ingress/tcp-services-postgres-configmap.yaml) and configure controller to read it.

Maintenance
- Keep manifests parameterized (kustomize/overlays or Helm) to manage dev/staging/prod differences.
- Put secrets outside git or in sealed-secrets/vault.

