# Infraestrutura como Código com Terraform e k3d

Este projeto utiliza Terraform para automatizar a criação de um ambiente de desenvolvimento local completo, rodando em um cluster k3d (Kubernetes em Docker).

Ele implanta os seguintes serviços, todos acessíveis via Ingress com SSL automático (Let's Encrypt):
- Keycloak: Gerenciamento de Identidade e Acesso.
- Minio: Armazenamento de objetos compatível com S3.
- PostgreSQL: Banco de dados relacional para o Keycloak.
- Traefik: Ingress Controller e roteador de tráfego para os serviços.
- ExternalDNS: Sincronização automática de registros DNS com o Cloudflare.
- Cert-Manager: Gerenciamento automático de certificados SSL.

### Host atual
- Sistema operacional: `Ubuntu 24.04.3 LTS`
- Placa-mãe: `MANCER MCR-A520M-DXV4`
- `AMD Ryzen 5 5600GT with Radeon Graphics`
- 6 núcleos / 12 threads
- Virtualização: `AMD-V`
- `16 GiB RAM`
- `4 GiB swap`

### Exposição externa
Tudo é exposto externamente via **Cloudflare**.

Isso significa que o fluxo esperado de publicação passa por:
- Cloudflare DNS
- ExternalDNS para sincronização automática de registros
- Traefik como Ingress Controller
- Cert-Manager para certificados TLS

## 1. Pré-requisitos

### Backup local do GitLab

As instrucoes especificas para configurar o disco `/dev/sdc2`, montar `/backup` e ativar os CronJobs de backup do GitLab estao em [README-backup.md](README-backup.md).

Para executar este projeto, as seguintes ferramentas precisam estar instaladas na máquina host (local ou servidor):

- git
- docker
- terraform
- k3d
- kubectl

## 2. Configuração do Cloudfla re

Para que o DNS e o SSL funcionem, você precisa configurar as credenciais do Cloudflare.

1. Crie um arquivo chamado terraform.tfvars na raiz do projeto (este arquivo é ignorado pelo Git).
2. Adicione suas credenciais:

```tfvars
cloudflare_api_token = "SEU_TOKEN_DE_API_DO_CLOUDFLARE"
# cloudflare_email = "SEU_EMAIL_DO_CLOUDFLARE" # Não é mais necessário com API Token
```

## 3. Implantação (O Fluxo em Etapas para CRDs)

Devido a dependências de CRDs (Custom Resource Definitions), é **crítico** seguir esta ordem estritamente para evitar erros de `API did not recognize GroupVersionKind` ou `no matches for kind`.

### Passo 0: Limpeza (opcional, mas recomendado para recomeçar do zero)
```bash
k3d cluster delete mycluster
rm -f .terraform.lock.hcl
rm -rf .terraform
rm -f terraform.tfstate*
rm -f .k3d_kubeconfig
```

### Passo 1: Inicializar o Terraform
```bash
terraform init
```

### Passo 2: Criar o Cluster k3d
Esta etapa cria o cluster Kubernetes e gera o arquivo `.k3d_kubeconfig`.

```bash
terraform apply -target=module.k3d_cluster
```

Responda `yes`.

### Passo 3: Instalar os CRDs do Cert-Manager
Instala o Cert-Manager via Helm, que é responsável por criar os CRDs de `ClusterIssuer` e `Certificate`.

```bash
terraform apply -target=module.networking.helm_release.cert_manager
```

Responda `yes`.

### Passo 4: Instalar os CRDs do Traefik
Aplica os CRDs necessários para o Traefik reconhecer recursos como `Middleware`.

```bash
terraform apply -target=module.traefik.null_resource.traefik_crds
```

Responda `yes`.

### Passo 5: Aplicar o restante da infraestrutura
Agora que todos os CRDs estão instalados, o Terraform pode aplicar o restante dos serviços, configurar os Ingresses e emitir os certificados.

```bash
terraform apply
```

Responda `yes`.

### 3.1 Atualizações futuras
Para qualquer alteração futura no código, após a instalação inicial:

```bash
terraform apply
```

## 4. Acessando os serviços e credenciais

Após a conclusão, os serviços estarão disponíveis via HTTPS.

### URLs
- Keycloak: `https://keycloak.avocadotech.site`
- Minio Console: `https://minio-console.avocadotech.site`
- Minio API (S3): `https://minio.avocadotech.site`
- Traefik Dashboard: `https://traefik.avocadotech.site`
- API Customizada: `https://api.avocadotech.site`

### Recuperando senhas
As senhas são geradas aleatoriamente e armazenadas no estado do Terraform.

#### Keycloak
- Usuário: `admin`
- Senha:
```bash
terraform output -raw keycloak_admin_password
```

#### Minio
- Usuário: `minioadmin` (ou o valor de `var.minio_access_key`)
- Senha:
```bash
terraform output -raw minio_secret_key
```

#### Postgres
- Senha:
```bash
terraform output -raw postgres_password
```

#### Traefik Dashboard
- Usuário: definido em `variables.tf` ou `terraform.tfvars`
- Senha:
```bash
terraform output -raw traefik_dashboard_password
```

## 5. Solução de problemas comuns (Troubleshooting)

### Cert-Manager: travado em `Pending` ou sem eventos
**Sintoma:** o certificado não é emitido e `kubectl describe challenge` não mostra eventos.

**Solução:**
1. Verifique se o Cert-Manager está rodando:
```bash
kubectl get pods -n cert-manager
```
2. Verifique o status do certificado:
```bash
kubectl get certificate
```
Se estiver `READY: False`, aguarde um pouco.
3. Apague o challenge travado para forçar nova tentativa:
```bash
kubectl delete challenge <nome-do-challenge-travado>
```
4. Se persistir, reinicie o controlador do Cert-Manager:
```bash
kubectl rollout restart deployment -n cert-manager
```

### Erro: `deployments.apps <recurso> already exists`
**Sintoma:** o Terraform falha ao tentar criar um recurso que já existe no cluster, mas não no estado.

**Solução:**
Importe o recurso para o estado do Terraform:
```bash
terraform import <tipo_do_recurso>.<nome_do_recurso> <namespace>/<nome_no_cluster>
```
Exemplo:
```bash
terraform import kubernetes_deployment_v1.keycloak default/keycloak
```

Ou apague o recurso do cluster para deixar o Terraform recriá-lo:
```bash
kubectl delete deployment <nome_do_deployment>
```

### Conexão via Tailscale / VPN
**Sintoma:** `terraform apply` falha com `i/o timeout` ao conectar no cluster remoto via Tailscale.

**Causa:** o IP do kubeconfig pode estar incorreto, por exemplo IP local do servidor em vez do IP da VPN.

**Solução:**
Substitua o IP no kubeconfig pelo IP do Tailscale:
```bash
sed -i "s/192.168.0.100/$(tailscale ip -4)/" .k3d_kubeconfig
```
Substitua `192.168.0.100` pelo IP original que estava no arquivo.

### Recriando certificados SSL
**Sintoma:** você precisa forçar a emissão de um novo certificado, por exemplo após mudar de servidor ou token.

**Causa:** o cert-manager não tem um pedido de certificado para processar.

**Solução:**
1. Garanta que seu token do Cloudflare está correto em `terraform.tfvars` ou via `TF_VAR_...`.
2. Force o Terraform a criar os recursos de certificado no cluster:
```bash
terraform apply -target=module.networking
```
3. Acompanhe o processo:
```bash
kubectl get certificate -w
```

### GitLab: erros de instalação ou redirect loop
**Sintoma:** o GitLab ou o Runner não conectam, ou o Helm acusa erro de `already exists`.

**Solução:**
1. Limpe os recursos órfãos no namespace. Isso não apaga seus dados do banco nem arquivos persistidos em PVCs:
```bash
kubectl delete deployment,service,ingress,configmap,secret,hpa -n gitlab --all --insecure-skip-tls-verify
```
2. Rode o `terraform apply` novamente para recriar tudo de forma limpa.
