# Backup Local do GitLab em `/backup`

Este documento descreve como configurar o disco `/dev/sdc2` como disco dedicado de backup e como ativar os CronJobs Kubernetes criados via Terraform para backup do GitLab.

## O Que Esta Configuracao Faz

- Prepara `/dev/sdc2` como disco de backup montado em `/backup`.
- Usa `UUID` no `/etc/fstab`, nunca `/dev/sdc2` diretamente.
- Cria os diretorios:
  - `/backup/gitlab`
  - `/backup/postgres`
  - `/backup/minio`
  - `/backup/registry`
  - `/backup/logs`
- Expoe `/backup/gitlab` ao Kubernetes via `hostPath`.
- Cria o CronJob `gitlab-backup` no namespace `gitlab`.
- Executa backup diario as `02:00`.
- Localiza dinamicamente o pod toolbox com o selector `app=toolbox,release=gitlab`.
- Executa `gitlab-backup create` dentro do container `toolbox`.
- Copia o arquivo final `*_gitlab_backup.tar` para `/backup/gitlab` no host.
- Cria o CronJob `gitlab-backup-cleanup` para remover backups com mais de 30 dias.

## Arquivos Terraform Envolvidos

- `backup-disk.tf`: preparo seguro do disco, montagem persistente e criacao dos diretorios.
- `gitlab-backup-cronjob.tf`: ServiceAccount, Role, RoleBinding, CronJob de backup e CronJob de limpeza.
- `variables.tf`: parametros de device, paths, horarios, retencao e selector do toolbox.
- `outputs.tf`: outputs dos paths e nomes dos CronJobs.
- `cluster.yaml`: bind mount `/backup:/backup` para os nodes k3d.
- `scripts/k3d_create.sh`: inclui `/backup` na lista real de volumes montados no k3d.

## Pre-Requisitos

- Ubuntu no host.
- Terraform instalado.
- `kubectl` configurado para acessar o cluster.
- `k3d` e Docker instalados, se o cluster for gerenciado por este projeto.
- A particao `/dev/sdc2` deve existir.
- `/dev/sda` deve permanecer reservado ao sistema operacional.
- `/dev/sdb1` deve permanecer reservado ao Docker em `/mnt/docker-data`.

## Seguranca do Disco

O Terraform foi escrito para ser conservador:

- Recusa operar em `/dev/sda*` e `/dev/sdb*`.
- Verifica se `/dev/sdc2` existe como block device.
- Se `/dev/sdc2` ja estiver montado em outro ponto, aborta.
- Se ja houver filesystem detectado por `blkid`, nao formata.
- Se nao houver filesystem, mas `wipefs -n` encontrar assinaturas, aborta para revisao manual.
- So executa `mkfs.ext4` quando nao ha filesystem nem assinaturas existentes.

Antes de aplicar, revise manualmente:

```bash
lsblk -f
sudo blkid /dev/sdc2 || true
sudo wipefs -n /dev/sdc2
mount | grep -E '/dev/sdc2|/backup' || true
```

## Variaveis Principais

Valores padrao:

```hcl
backup_device                     = "/dev/sdc2"
backup_mount_point                = "/backup"
gitlab_backup_host_path           = "/backup/gitlab"
gitlab_backup_schedule            = "0 2 * * *"
gitlab_backup_cleanup_schedule    = "30 3 * * *"
gitlab_backup_retention_days      = 30
gitlab_toolbox_label_selector     = "app=toolbox,release=gitlab"
gitlab_backup_kubectl_image       = "bitnami/kubectl:1.30"
```

Se precisar alterar, use `terraform.tfvars`:

```hcl
backup_device                  = "/dev/sdc2"
gitlab_backup_schedule         = "0 2 * * *"
gitlab_backup_retention_days   = 30
gitlab_toolbox_label_selector  = "app=toolbox,release=gitlab"
```

## Atencao Para k3d e `hostPath`

Em k3d, `hostPath` aponta para o filesystem do container do node, nao diretamente para o host fisico. Por isso o projeto monta `/backup:/backup` nos nodes k3d.

Se o cluster ainda nao existe, o `terraform apply` criara o cluster ja com o mount correto.

Se o cluster ja existe e foi criado sem `/backup`, o script `scripts/k3d_create.sh` abortara com uma mensagem pedindo recriacao. Nesse caso, recrie apenas depois de confirmar que os workloads podem ser recriados:

```bash
FORCE_RECREATE=1 terraform apply
```

## Aplicar a Configuracao

Inicialize providers e modulos:

```bash
terraform init
```

Revise o plano:

```bash
terraform plan
```

Aplique:

```bash
terraform apply
```

## Validar o Disco no Host

```bash
df -h /backup
mount | grep /backup
findmnt /backup
cat /etc/fstab | grep /backup
ls -lah /backup
ls -lah /backup/gitlab
```

A entrada no `/etc/fstab` deve usar `UUID=...`, nao `/dev/sdc2`.

## Validar Recursos Kubernetes

```bash
kubectl get serviceaccount,role,rolebinding -n gitlab | grep gitlab-backup
kubectl get cronjob -n gitlab
kubectl describe cronjob gitlab-backup -n gitlab
kubectl describe cronjob gitlab-backup-cleanup -n gitlab
```

Verifique se o toolbox e localizado pelo selector configurado:

```bash
kubectl get pods -n gitlab -l app=toolbox,release=gitlab
```

Se nao retornar o pod toolbox, ajuste `gitlab_toolbox_label_selector` em `terraform.tfvars`.

## Executar Backup Manual

Crie um Job manual a partir do CronJob:

```bash
kubectl create job --from=cronjob/gitlab-backup gitlab-backup-manual -n gitlab
```

Acompanhe:

```bash
kubectl logs job/gitlab-backup-manual -n gitlab -f
```

Confirme o arquivo no host:

```bash
ls -lah /backup/gitlab
```

## Validar Limpeza de Backups Antigos

O CronJob de limpeza remove arquivos em `/backup/gitlab` com nome `*_gitlab_backup.tar` e idade maior que `gitlab_backup_retention_days`.

Listar CronJob:

```bash
kubectl get cronjob gitlab-backup-cleanup -n gitlab
```

Executar manualmente:

```bash
kubectl create job --from=cronjob/gitlab-backup-cleanup gitlab-backup-cleanup-manual -n gitlab
kubectl logs job/gitlab-backup-cleanup-manual -n gitlab -f
```

## GitLab Helm Chart e Backup Nativo

O chart do GitLab possui suporte nativo a backup via toolbox em `gitlab.toolbox.backups.cron.enabled`.

Neste projeto foi mantido um CronJob customizado porque o requisito local e especifico:

- executar `gitlab-backup create` no pod toolbox existente;
- localizar o pod dinamicamente;
- copiar o backup final para `/backup/gitlab` no host;
- usar `hostPath` apontando para o disco fisico de backup.

O backup nativo do chart continua sendo uma alternativa futura se o destino passar a ser object storage ou um PVC gerenciado pelo chart.

## Troubleshooting

### CronJob nao encontra o toolbox

Verifique labels reais:

```bash
kubectl get pods -n gitlab --show-labels | grep toolbox
```

Atualize em `terraform.tfvars`:

```hcl
gitlab_toolbox_label_selector = "app=toolbox,release=gitlab"
```

Depois aplique:

```bash
terraform apply
```

### Backup foi salvo dentro do node k3d, nao no host

Verifique se `/backup` esta montado no container do node:

```bash
docker inspect k3d-mycluster-server-0 --format '{{range .Mounts}}{{println .Source "->" .Destination}}{{end}}' | grep /backup
```

Se nao houver mount, recrie o cluster com cuidado:

```bash
FORCE_RECREATE=1 terraform apply
```

### Terraform falha ao preparar o disco

Revise se a particao existe e nao esta montada em outro lugar:

```bash
lsblk -f
findmnt -S /dev/sdc2 || true
sudo blkid /dev/sdc2 || true
sudo wipefs -n /dev/sdc2
```

Se houver assinaturas antigas e voce tiver certeza de que o disco pode ser apagado, limpe manualmente antes de reaplicar. Nao automatize isso sem revisar os dados.

### Validar permissao de escrita no hostPath

```bash
kubectl create job --from=cronjob/gitlab-backup gitlab-backup-manual -n gitlab
kubectl logs job/gitlab-backup-manual -n gitlab
ls -lah /backup/gitlab
```
