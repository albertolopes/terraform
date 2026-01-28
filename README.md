# Infraestrutura como Código com Terraform e k3d

Este projeto utiliza Terraform para automatizar a criação de um ambiente de desenvolvimento local completo, rodando em um cluster k3d (Kubernetes em Docker).

Ele implanta os seguintes serviços, todos acessíveis via Ingress:
- **Keycloak:** Gerenciamento de Identidade e Acesso.
- **Minio:** Armazenamento de objetos compatível com S3.
- **PostgreSQL:** Banco de dados relacional para o Keycloak.
- **Nginx:** Servidor web de exemplo.
- **ExternalDNS:** Sincronização automática de registros DNS com o Cloudflare.

## 1. Pré-requisitos

Para executar este projeto, as seguintes ferramentas precisam estar instaladas na máquina host (local ou servidor):

- `git`
- `docker`
- `terraform`
- `k3d`
- `kubectl`

## 2. Script de Instalação (Para Ubuntu Server)

Se você estiver em um Ubuntu Server novo, pode usar o script abaixo para instalar todas as dependências de uma vez.

```sh
#!/bin/bash
# ... (script de instalação completo aqui) ...
```

**IMPORTANTE:** Após executar o script, você **precisa** fazer logout e login novamente para que as permissões do Docker sejam aplicadas ao seu usuário.

## 3. Como Usar

### 3.1. Configuração do Cloudflare (Apenas uma vez)

Este projeto usa o `external-dns` para gerenciar automaticamente os registros DNS no Cloudflare. Para isso, você precisa criar um Token de API:

1. No painel da Cloudflare, vá para "My Profile" > "API Tokens".
2. Clique em "Create Token" e use o template "Edit zone DNS".
3. Em "Zone Resources", selecione a sua zona específica (ex: `moedabot.xyz`).
4. Crie o token e copie-o.

### 3.2. Implantação com Terraform

**Passo 0: Limpeza (Opcional, mas recomendado)**
```sh
k3d cluster delete mycluster
rm -f .terraform.lock.hcl
rm -rf .terraform
rm -f terraform.tfstate*
```

**Passo 1: Inicializar o Terraform**
```sh
terraform init
```

**Passo 2: Definir o Token do Cloudflare**
Antes de executar o `apply`, defina o token que você criou como uma variável de ambiente. Esta é a forma mais segura de passar segredos para o Terraform.

```sh
export TF_VAR_cloudflare_api_token="<SEU_TOKEN_DO_CLOUDFLARE>"
```

**Passo 3: Criar Apenas o Cluster**
Use a flag `-target` para forçar a criação apenas do cluster k3d.

```sh
terraform apply -target=null_resource.k3d_cluster
```
Responda `yes` quando solicitado.

**Passo 4: Criar Todos os Outros Serviços**
Agora, execute o `apply` normal para criar os segredos, os serviços, os deployments, o ingress e o `external-dns`.

```sh
terraform apply
```
Responda `yes` quando solicitado.

### 3.3. Atualizações Futuras

Para qualquer alteração futura no código, você só precisa definir a variável de ambiente e executar o `apply`:

```sh
export TF_VAR_cloudflare_api_token="<SEU_TOKEN_DO_CLOUDFLARE>"
terraform apply
```

## 4. Acessando os Serviços

Após a conclusão do `apply`, o `external-dns` terá criado automaticamente os registros DNS. Os serviços estarão disponíveis nos seguintes endereços:

- **Keycloak:** `http://keycloak.moedabot.xyz`
- **Minio Console:** `http://minio-console.moedabot.xyz`
- **Minio API (S3):** `http://minio.moedabot.xyz`

## 5. Solução de Problemas Comuns

### Erro de "Permission Denied" ao Conectar ao Docker

Se você ver um erro como `permission denied while trying to connect to the Docker daemon socket`, sua sessão de terminal atual não tem as permissões corretas.

**Solução 1 (Recomendada):** Faça logout do servidor e faça login novamente.

**Solução 2 (Rápida):** Execute `newgrp docker` no seu terminal atual antes de rodar os comandos do Terraform.


### External DNS
# Remova as chaves antigas e deixe apenas CF_API_TOKEN
kubectl create secret generic cloudflare-credentials \
--namespace=default \
--from-literal=CF_API_TOKEN='TOKEN' \
--dry-run=client -o yaml | kubectl apply -f -

# Verifique o secret
kubectl get secret cloudflare-credentials -n default -o jsonpath='{.data.CF_API_TOKEN}' | base64 -d
echo ""

echo 'export TF_VAR_cloudflare_api_token="TOKEN"' >> ~/.bashrc
source ~/.bashrc
