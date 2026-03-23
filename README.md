# Infraestrutura como Código com Terraform e k3d

Este projeto utiliza Terraform para automatizar a criação de um ambiente de desenvolvimento local completo, rodando em um cluster k3d (Kubernetes em Docker).

Ele implanta os seguintes serviços, todos acessíveis via Ingress com SSL automático (Let's Encrypt):
- **Keycloak:** Gerenciamento de Identidade e Acesso.
- **Minio:** Armazenamento de objetos compatível com S3.
- **PostgreSQL:** Banco de dados relacional para o Keycloak.
- **Nginx:** Servidor web de exemplo.
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
cloudflare_api_key = "SUA_CHAVE_GLOBAL_AQUI"
cloudflare_email   = "SEU_EMAIL_AQUI"
```

## 3. Implantação (O Fluxo de 3 Etapas)

Devido a dependências de CRDs (Custom Resource Definitions) do Kubernetes, a implantação inicial deve ser feita em três etapas para evitar erros de "resource not found".

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

**Passo 2: Criar a Infraestrutura Básica**
Isso cria o cluster, o banco de dados, o Keycloak e o Nginx.
```sh
terraform apply -target=module.k3d_cluster -target=module.postgres -target=module.minio -target=module.keycloak -target=module.nginx
```
Responda `yes` quando solicitado.

**Passo 3: Instalar o Cert-Manager**
Isso instala o Cert-Manager e registra as CRDs necessárias.
```sh
-target
```
Responda `yes` quando solicitado.

**Passo 4: Configurar SSL e Finalizar**
Agora que as CRDs existem, podemos criar os emissores de certificado e aplicar o restante da configuração.
```sh
terraform apply
```
Responda `yes` quando solicitado.

### 3.1. Atualizações Futuras

Para qualquer alteração futura no código, você só precisa executar:

```sh
terraform apply
```

## 4. Acessando os Serviços

Após a conclusão, os serviços estarão disponíveis via HTTPS com certificados válidos:

- **Keycloak:** `https://keycloak.moedabot.xyz`
- **Minio Console:** `https://minio-console.moedabot.xyz`
- **Minio API (S3):** `https://minio.moedabot.xyz`
- **API Customizada:** `https://api.moedabot.xyz`

## 5. Solução de Problemas Comuns

### Erro de DNS "i/o timeout"

Se o Terraform falhar ao baixar charts do Helm com erros de DNS, verifique se o seu servidor está usando servidores DNS válidos. Em um servidor Ubuntu, você pode precisar forçar o uso do DNS do Google (8.8.8.8) editando `/etc/systemd/resolved.conf`.
