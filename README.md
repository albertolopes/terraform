# Infraestrutura como Código com Terraform e k3d

Este projeto utiliza Terraform para automatizar a criação de um ambiente de desenvolvimento local completo, rodando em um cluster k3d (Kubernetes em Docker).

Ele implanta os seguintes serviços, todos acessíveis via Ingress com SSL automático (Let's Encrypt):
- **Keycloak:** Gerenciamento de Identidade e Acesso.
- **Minio:** Armazenamento de objetos compatível com S3.
- **PostgreSQL:** Banco de dados relacional para o Keycloak.
- **Nginx:** Servidor web de exemplo e Ingress Controller.
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
cloudflare_email     = "SEU_EMAIL_DO_CLOUDFLARE"
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
terraform apply -target=module.networking.helm_release.cert_manager
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

## 4. Acessando os Serviços e Credenciais

Após a conclusão, os serviços estarão disponíveis via HTTPS.

### URLs
- **Keycloak:** `https://keycloak.avocadotech.site`
- **Minio Console:** `https://minio-console.avocadotech.site`
- **Minio API (S3):** `https://minio.avocadotech.site`
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

## 5. Solução de Problemas Comuns (Troubleshooting)

### Nginx: "cannot load certificate ... no such file"
**Sintoma:** O pod do Nginx fica reiniciando com erro de `emerg` dizendo que não acha `tls.crt`.
**Causa:** O Certificado ainda não foi emitido pelo Cert-Manager, então o segredo `nginx-certs` não existe.
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
3.  Se o segredo já existe (`kubectl get secret nginx-certs`) e o erro persiste, o Nginx pode estar com configuração antiga. Force a recriação dos pods:
    ```sh
    kubectl delete pods -l app=nginx
    ```

### Cert-Manager: Travado em "Pending" ou sem Eventos
**Sintoma:** O certificado não é emitido. `kubectl describe challenge` não mostra eventos.
**Solução:**
1.  Apague o challenge travado para forçar o Cert-Manager a tentar de novo:
    ```sh
    kubectl delete challenge <nome-do-challenge-travado>
    ```
2.  Se persistir, reinicie o controlador do Cert-Manager:
    ```sh
    kubectl rollout restart deployment cert-manager -n cert-manager
    ```

### Nginx: Redirecionamento Incorreto ou Configuração Antiga
**Sintoma:** Você acessa `minio-console...` mas cai no Keycloak, ou o Nginx não reflete mudanças recentes no `nginx.conf`.
**Causa:** O Terraform atualizou o ConfigMap, mas o Pod do Nginx não recarregou o arquivo.
**Solução:**
1.  Force a atualização do ConfigMap:
    ```sh
    terraform taint module.nginx.kubernetes_config_map_v1.nginx_config
    terraform apply -target=module.nginx.kubernetes_config_map_v1.nginx_config
    ```
2.  Mate os pods para forçar a leitura da nova configuração:
    ```sh
    kubectl delete pods -l app=nginx
    ```

### Erro: "deployments.apps nginx already exists"
**Sintoma:** O Terraform falha ao tentar criar um recurso que já existe no cluster (mas não no estado).
**Solução:** Importe o recurso para o estado do Terraform:
```sh
terraform import module.nginx.kubernetes_deployment_v1.nginx default/nginx
```
Ou apague o recurso do cluster para deixar o Terraform recriar:
```sh
kubectl delete deployment nginx
```
