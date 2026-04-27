# Infraestrutura como Código com Terraform e k3d

Este projeto utiliza Terraform para automatizar a criação de um ambiente de desenvolvimento local completo, rodando em um cluster k3d (Kubernetes em Docker).

Ele implanta os seguintes serviços, todos acessíveis via Ingress com SSL automático (Let's Encrypt):
- **Keycloak:** Gerenciamento de Identidade e Acesso.
- **Minio:** Armazenamento de objetos compatível com S3.
- **PostgreSQL:** Banco de dados relacional para o Keycloak.
- **Traefik:** Ingress Controller e roteador de tráfego para os serviços.
- **ExternalDNS:** Sincronização automática de registros DNS com o Cloudflare.
- **Cert-Manager:** Gerenciamento automático de certificados SSL.

## 1. Pré-requisitos

Para executar este projeto, as seguintes ferramentas precisam estar instaladas na máquina host (local ou servidor):

- `git`
- `docker`
- `terraform`
- `k3d`
- `kubectl`

## 2. Configuração do Cloudflare

Para que o DNS e o SSL funcionem, você precisa configurar as credenciais do Cloudflare.

1.  Crie um arquivo chamado `terraform.tfvars` na raiz do projeto (este arquivo é ignorado pelo Git).
2.  Adicione suas credenciais:

```hcl
cloudflare_api_token = "SEU_TOKEN_DE_API_DO_CLOUDFLARE"
# cloudflare_email     = "SEU_EMAIL_DO_CLOUDFLARE" # Não é mais necessário com API Token
```

## 3. Implantação (O Fluxo em Etapas para CRDs)

Devido a dependências de CRDs (Custom Resource Definitions), é **CRÍTICO** seguir esta ordem estritamente para evitar erros de "API did not recognize GroupVersionKind" ou "no matches for kind".

**Passo 0: Limpeza (Opcional, mas recomendado para recomeçar do zero)**
```sh
k3d cluster delete mycluster
rm -f .terraform.lock.hcl
rm -rf .terraform
rm -f terraform.tfstate*
rm -f .k3d_kubeconfig # Remova o kubeconfig gerado
```

**Passo 1: Inicializar o Terraform**
```sh
terraform init
```

**Passo 2: Criar o Cluster k3d**
Esta etapa cria o cluster Kubernetes e gera o arquivo `.k3d_kubeconfig`.
```sh
terraform apply -target=module.k3d_cluster
```
Responda `yes`.

**Passo 3: Instalar os CRDs do Cert-Manager**
Instala o Cert-Manager via Helm, que é responsável por criar os CRDs de `ClusterIssuer` e `Certificate`.
```sh
terraform apply -target=module.networking.helm_release.cert_manager
```
Responda `yes`.

**Passo 4: Instalar os CRDs do Traefik**
Aplica os CRDs necessários para o Traefik reconhecer recursos como `Middleware`.
```sh
terraform apply -target=module.traefik.null_resource.traefik_crds
```
Responda `yes`.

**Passo 5: Aplicar o Restante da Infraestrutura**
Agora que todos os CRDs estão instalados, o Terraform pode aplicar o restante dos serviços (Keycloak, Minio, Traefik, etc.) e configurar os Ingresses e Certificados.
```sh
terraform apply
```
Responda `yes`.

### 3.1. Atualizações Futuras

Para qualquer alteração futura no código (após a instalação inicial), você só precisa executar:

```sh
terraform apply
```

## 4. Acessando os Serviços e Credenciais

Após a conclusão, os serviços estarão disponíveis via HTTPS.

### URLs
- **Keycloak:** `https://keycloak.avocadotech.site`
- **Minio Console:** `https://minio-console.avocadotech.site`
- **Minio API (S3):** `https://minio.avocadotech.site`
- **Traefik Dashboard:** `https://traefik.avocadotech.site`
- **API Customizada:** `https://api.avocadotech.site`

### Recuperando Senhas
As senhas são geradas aleatoriamente e armazenadas no estado do Terraform. Para vê-las:

**Keycloak:**
- Usuário: `admin`
- Senha:
  ```sh
  terraform output -raw keycloak_admin_password
  ```

**Minio:**
- Usuário: `minioadmin` (ou o valor de var.minio_access_key)
- Senha:
  ```sh
  terraform output -raw minio_secret_key
  ```

**Postgres:**
- Senha:
  ```sh
  terraform output -raw postgres_password
  ```
  
**Traefik Dashboard:**
- Usuário: (definido em `variables.tf` ou `terraform.tfvars`)
- Senha:
  ```sh
  terraform output -raw traefik_dashboard_password
  ```

## 5. Solução de Problemas Comuns (Troubleshooting)

### Cert-Manager: Travado em "Pending" ou sem Eventos
**Sintoma:** O certificado não é emitido. `kubectl describe challenge` não mostra eventos.
**Solução:**
1.  Verifique se o Cert-Manager está rodando:
    ```sh
    kubectl get pods -n cert-manager
    ```
2.  Verifique o status do certificado:
    ```sh
    kubectl get certificate
    ```
    Se estiver `READY: False`, aguarde.
3.  Apague o challenge travado para forçar o Cert-Manager a tentar de novo:
    ```sh
    kubectl delete challenge <nome-do-challenge-travado>
    ```
4.  Se persistir, reinicie o controlador do Cert-Manager:
    ```sh
    kubectl rollout restart deployment -n cert-manager
    ```

### Erro: "deployments.apps <recurso> already exists"
**Sintoma:** O Terraform falha ao tentar criar um recurso que já existe no cluster (mas não no estado).
**Solução:** Importe o recurso para o estado do Terraform:
```sh
terraform import <tipo_do_recurso>.<nome_do_recurso> <namespace>/<nome_no_cluster>
# Exemplo: terraform import kubernetes_deployment_v1.keycloak default/keycloak
```
Ou apague o recurso do cluster para deixar o Terraform recriar:
```sh
kubectl delete deployment <nome_do_deployment>
```

### Conexão via Tailscale / VPN
**Sintoma:** `terraform apply` falha com `i/o timeout` ao conectar no cluster remoto via Tailscale.
**Causa:** O IP do kubeconfig pode estar incorreto (IP local do servidor em vez do IP da VPN).
**Solução:** Substitua o IP no kubeconfig pelo IP do Tailscale:
```sh
sed -i "s/192.168.0.100/$(tailscale ip -4)/" .k3d_kubeconfig
```
(Substitua `192.168.0.100` pelo IP original que estava no arquivo).

### Recriando Certificados SSL
**Sintoma:** Você precisa forçar a emissão de um novo certificado (por exemplo, após mudar de servidor ou token).
**Causa:** O `cert-manager` não tem um pedido de certificado para processar.
**Solução:**
1.  Garanta que seu token do Cloudflare está correto (no `terraform.tfvars` ou `export TF_VAR_...`).
2.  Force o Terraform a criar os recursos de certificado no cluster:
    ```sh
    terraform apply -target=module.networking
    ```
3.  Acompanhe o processo:
    ```sh
    kubectl get certificate -w
    ```
### GitLab: Erros de instalação ou redirect loop
**Sintoma:** O GitLab ou o Runner não conectam, ou o Helm acusa erro de "already exists".
**Solução:**
1.  Limpe os recursos órfãos no namespace (isso não apaga seus dados do banco ou arquivos):
    ```sh
    # Deleta quase tudo no namespace gitlab (não deleta os PVCs)
    kubectl delete deployment,service,ingress,configmap,secret,hpa -n gitlab --all --insecure-skip-tls-verify
    ```
2.  Rode o `terraform apply` novamente para que ele recrie tudo de forma limpa.
