#!/usr/bin/env bash
# ==============================================================================
# Wrapper de cron para el backup de etcd ejecutado desde el CONTROLADOR Ansible.
# Copia el snapshot más reciente de RKE2 de cada control plane a los backup servers.
#
# Instalación (en el controlador Ansible, como el usuario que tiene las claves SSH):
#   crontab -e
#   # Cada 4 horas, en el minuto 0:
#   0 */4 * * *  /ruta/al/repo/scripts/etcd-backup-cron.sh >> /var/log/etcd-backup.log 2>&1
# ==============================================================================
set -euo pipefail

# Raíz del proyecto = carpeta padre de este script (resuelve symlinks).
PROJECT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
LOCK_FILE="/tmp/etcd-backup-cron.lock"

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [etcd-backup-cron] $*"; }

cd "${PROJECT_DIR}"

# Evita ejecuciones solapadas si una corrida previa sigue activa.
exec 9>"${LOCK_FILE}"
if ! flock -n 9; then
    log "Otra ejecución de backup sigue en curso. Abortando esta corrida."
    exit 0
fi

log "Iniciando backup de etcd (transfer + prune) desde el controlador..."
ansible-playbook site.yml --tags backup_run
log "Backup de etcd finalizado correctamente."
