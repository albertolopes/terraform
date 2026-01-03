#!/usr/bin/env bash
set -euo pipefail
KUBECONFIG="${1:-./.k3d_kubeconfig}"

# DELETE ARQUIVO
# Este arquivo foi removido do fluxo de apply por solicitação do usuário.
# Ele anteriormente fazia a remoção agressiva do PV/PVC do Postgres.
# Manter este arquivo apagado evita exclusão acidental do PVC.
exit 0
