# Contexto de Proyecto: Ansible etcd Backup & Disaster Recovery para RKE2

Este documento sirve como referencia rápida de contexto para el proyecto de automatización de copias de seguridad consistentes de `etcd` y el plan de recuperación ante desastres (DR) para clústeres Kubernetes sobre RKE2.

## 🏛️ Resumen del Proyecto y Arquitectura

RKE2 genera snapshots automáticos de `etcd` de forma nativa en cada control plane (`/var/lib/rancher/rke2/server/db/snapshots`). 
Este proyecto **no inicia snapshots nuevos**; localiza el snapshot `.db` más reciente y lo transfiere a servidores de almacenamiento centralizados para retención a largo plazo.

### Flujo de Copia (Transferencia)
Soporta dos modos de red (`etcd_transfer_mode`):
1. **`controller_mediated`** (Por defecto): El orquestador Ansible actúa como puente seguro. Descarga el snapshot desde el master y luego lo sube al storage remoto (ideal para redes segmentadas).
2. **`direct_rsync`**: Conexión rsync directa entre los control planes y los servidores de backup (requiere claves SSH cruzadas y apertura de puertos).

---

## ⚙️ Configuración y Variables Clave

### Inventario (`inventories/production/hosts.yml`)
- **`control_planes`**: Lista de masters Kubernetes (ej. `k8s-master-01`, `02`, `03`).
- **`backup_servers`**: Servidores remotos de destino (ej. `backup-storage-01`, `02`).

### Variables de Configuración (`inventories/production/group_vars/all.yml`)
- `rke2_snapshot_dir`: `/var/lib/rancher/rke2/server/db/snapshots` (origen).
- `etcd_backup_server_dir`: `/srv/backup/kubernetes/etcd` (destino).
- `etcd_backup_server_retention_count`: `3` (copias a mantener por master).
- `etcd_transfer_mode`: `"controller_mediated"`.
- Configuración de conexión (`ansible_user` y `ansible_ssh_private_key_file`).

---

## 🚀 Playbooks Principales

### 1. `site.yml` (Backup)
Usa el rol `etcd_backup` para transferir copias y aplicar políticas de retención.
- Comando para ejecutar backup completo:
  ```bash
  ansible-playbook site.yml --tags backup_run
  ```
- Tags útiles: `backup_transfer` (copiar archivo), `backup_prune` (limpiar antiguos).
- Automatización programada: Wrapper script en `/scripts/etcd-backup-cron.sh` para programarse en el crontab del controlador Ansible.

### 2. `restore.yml` (Restauración de Desastres)
Usa el rol `etcd_restore` para restaurar un snapshot.
> [!WARNING]
> La restauración es destructiva. Detendrá temporalmente el control plane de RKE2 y reiniciará el clúster. Requiere confirmación manual escribiendo la palabra `CONFIRMAR`.

El playbook realiza de forma autónoma:
1. Localiza el snapshot en la fuente (`backup_server` o `controller` local).
2. Detiene `rke2-server` en todos los control planes.
3. Ejecuta `rke2 server --cluster-reset` en el nodo primario con la copia.
4. Reinicia `rke2-server` en el primario y espera a que responda.
5. Limpia `db/etcd` en los demás control planes y los reinicia para reincorporarlos en alta disponibilidad (HA).
6. Valida la salud del clúster final con `kubectl get nodes`.

Ejemplo de comando:
```bash
ansible-playbook restore.yml
```
O especificando una ruta o archivo:
```bash
ansible-playbook restore.yml -e "etcd_restore_file_path=mi-snapshot"
```
