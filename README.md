# Infraestrutura como Código com Terraform e k3d

Este projeto utiliza Terraform para automatizar a criação de um ambiente de desenvolvimento local completo, rodando em um cluster k3d (Kubernetes em Docker).

Ele implanta os seguintes serviços, todos acessíveis via Ingress:
- **Keycloak:** Gerenciamento de Identidade e Acesso.
- **Minio:** Armazenamento de objetos compatível com S3.
- **PostgreSQL:** Banco de dados relacional para o Keycloak.
- **Nginx:** Servidor web de exemplo.

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
set -euo pipefail

# --- ATUALIZAR O SISTEMA ---
echo "### 1/6: Atualizando pacotes do sistema..."
sudo apt-get update
sudo apt-get upgrade -y

# --- INSTALAR DEPENDÊNCIAS BÁSICAS (git, curl, etc.) ---
echo "### 2/6: Instalando dependências básicas (git, curl)..."
sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release git

# --- INSTALAR DOCKER ---
echo "### 3/6: Instalando o Docker..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io
# Adicionar o usuário atual ao grupo do Docker para não precisar de 'sudo'
sudo usermod -aG docker $USER
echo "Docker instalado. Você precisará fazer logout e login novamente para usar o Docker sem sudo."

# --- INSTALAR TERRAFORM ---
echo "### 4/6: Instalando o Terraform..."
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
sudo apt-get update
sudo apt-get install -y terraform

# --- INSTALAR KUBECTL ---
echo "### 5/6: Instalando o kubectl..."
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl

# --- INSTALAR K3D ---
echo "### 6/6: Instalando o k3d..."
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

# --- VERIFICAÇÃO FINAL ---
echo "--------------------------------------------------"
echo "Instalação concluída! Verificando as versões..."
docker --version
terraform --version
kubectl version --client
k3d --version
echo "--------------------------------------------------"
echo "IMPORTANTE: Por favor, faça logout e login novamente para que as permissões do Docker sejam aplicadas."
echo "--------------------------------------------------"
```

**IMPORTANTE:** Após executar o script, você **precisa** fazer logout e login novamente para que as permissões do Docker sejam aplicadas ao seu usuário.

## 3. Como Usar

Devido a uma limitação do Terraform (condição de corrida na inicialização dos provedores), a criação do ambiente do zero precisa ser feita em duas etapas.

### 3.1. Criação Inicial (Do Zero)

**Passo 0: Limpeza (Opcional, mas recomendado)**

Se você já teve tentativas anteriores, limpe tudo para garantir um ambiente 100% novo.

```sh
k3d cluster delete mycluster
rm -f .terraform.lock.hcl
rm -rf .terraform
rm -f terraform.tfstate*
```

**Passo 1: Inicializar o Terraform**

Isso irá baixar os provedores necessários.

```sh
terraform init
```

**Passo 2: Criar Apenas o Cluster**

Use a flag `-target` para forçar a criação apenas do cluster k3d.

```sh
terraform apply -target=null_resource.k3d_cluster
```
Responda `yes` quando solicitado.

**Passo 3: Criar Todos os Outros Serviços**

Agora que o cluster existe, execute o `apply` normal para criar os segredos, os serviços, os deployments e o ingress.

```sh
terraform apply
```
Responda `yes` quando solicitado.

### 3.2. Atualizações Futuras

Após a criação inicial, para qualquer alteração futura no código, você só precisa executar o comando padrão:

```sh
terraform apply
```

## 4. Acessando os Serviços

Após a conclusão do `apply`, os serviços estarão disponíveis nos seguintes endereços. Não é necessário editar o arquivo `/etc/hosts`.

- **Keycloak:** `http://keycloak.moedabot.xyz`
- **Minio Console:** `http://minio-console.moedabot.xyz`
- **Minio API (S3):** `http://minio.moedabot.xyz`

**Nota:** Para que esses domínios funcionem, você precisa ter um registro DNS curinga (`A` record com nome `*`) no seu provedor de DNS (Cloudflare) apontando para o endereço de IP público do seu servidor.
