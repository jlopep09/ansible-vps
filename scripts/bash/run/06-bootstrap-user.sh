#!/usr/bin/env bash

set -euo pipefail

ENV_FILE="./.env"
ANSIBLE_DIR="./ansible"
INVENTORY="$ANSIBLE_DIR/inventory.ini"
PLAYBOOK="$ANSIBLE_DIR/playbooks/user.yml"

# Cargar funciones de ssh-agent
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=00-ssh-agent-utils.sh
source "$SCRIPT_DIR/00-ssh-agent-utils.sh"

# ============================================================
# FUNCIONES
# ============================================================

error() {
    echo
    echo "[ERROR] $1"
    exit 1
}

load_env() {
    if [[ ! -f "$ENV_FILE" ]]; then
        error "No existe $ENV_FILE"
    fi

    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
}

require_variable() {
    local variable="$1"

    if [[ -z "${!variable:-}" ]]; then
        error "Falta la variable $variable en $ENV_FILE"
    fi
}

# ============================================================
# INICIO
# ============================================================

echo "========================================="
echo " Configuración inicial del usuario VPS"
echo "========================================="
echo

# Cargar .env
load_env

require_variable "VPS_IP"
require_variable "VPS_USER"
require_variable "VPS_PASSWORD"
require_variable "SSH_PRIVATE_KEY"
require_variable "SSH_PUBLIC_KEY"

# Comprobar archivos
if [[ ! -f "$PLAYBOOK" ]]; then
    error "No existe el playbook: $PLAYBOOK"
fi

if [[ ! -f "$SSH_PRIVATE_KEY" ]]; then
    error "No existe la clave privada: $SSH_PRIVATE_KEY"
fi

chmod 600 "$SSH_PRIVATE_KEY"

# Asegurar que el inventario y las variables del playbook de usuario existan
# antes de ejecutarlo. El playbook depende de username y ssh_public_key en ansible/group_vars/user.yml.
if [[ ! -f "$ANSIBLE_DIR/group_vars/user.yml" ]] || ! grep -q 'username:' "$ANSIBLE_DIR/group_vars/user.yml"; then
    echo "[INFO] Generando variables de Ansible para el playbook de usuario..."
    "$SCRIPT_DIR/05-generate-ansible-vars.sh"
fi

# Asegurar que el inventario final no quede en un estado antiguo antes del bootstrap
cat > "$INVENTORY" <<EOF
[vps]
$VPS_IP ansible_user=root ansible_port=22
EOF

# ============================================================
# Ejecutar Ansible para crear usuario usando root
# ============================================================

TEMP_INVENTORY="$(mktemp)"
trap 'rm -f "$TEMP_INVENTORY"' EXIT

cat > "$TEMP_INVENTORY" <<EOF
[vps]
$VPS_IP ansible_user=root ansible_port=22
EOF

echo "[INFO] Inventory temporal de bootstrap:"
echo
cat "$TEMP_INVENTORY"
echo

echo "========================================="
echo " Creando usuario VPS"
echo "========================================="
echo

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
ssh-keygen -f "$HOME/.ssh/known_hosts" -R "$VPS_IP" 2>/dev/null || true

export ANSIBLE_HOST_KEY_CHECKING=False

 echo "[INFO] Conectando como root a $VPS_IP..."
echo "[INFO] Creando usuario $VPS_USER..."
echo

if ! ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook \
    "$PLAYBOOK" \
    -i "$TEMP_INVENTORY" \
    -e "ansible_password=$VPS_PASSWORD" \
    -e "ansible_ssh_common_args='-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$HOME/.ssh/known_hosts'" \
    -e "username=$VPS_USER" \
    -e "ssh_public_key=$(cat "$SSH_PUBLIC_KEY")"
then
    error "El playbook de creación del usuario ha fallado."
fi

echo
echo "[OK] Usuario $VPS_USER creado/configurado correctamente."

echo
echo "[INFO] Instalando la clave pública del usuario $VPS_USER en el servidor..."

SSH_PUBLIC_KEY_CONTENT="$(tr -d '\r' < "$SSH_PUBLIC_KEY")"

if ! sshpass -p "$VPS_PASSWORD" ssh \
    -o StrictHostKeyChecking=accept-new \
    -o UserKnownHostsFile="$HOME/.ssh/known_hosts" \
    -o ConnectTimeout=15 \
    -o LogLevel=ERROR \
    "root@$VPS_IP" \
    "bash -lc 'install -d -m 700 -o $VPS_USER -g $VPS_USER /home/$VPS_USER/.ssh; printf %s \"$SSH_PUBLIC_KEY_CONTENT\\n\" > /home/$VPS_USER/.ssh/authorized_keys; chown $VPS_USER:$VPS_USER /home/$VPS_USER/.ssh/authorized_keys; chmod 600 /home/$VPS_USER/.ssh/authorized_keys'"
then
    error "No se pudo instalar la clave pública autorizada para $VPS_USER."
fi

echo "[OK] Clave pública instalada correctamente en el servidor."

# Actualizar inventory para usar el usuario no-root
echo
echo "[INFO] Actualizando inventory de Ansible..."

cat > "$INVENTORY" <<EOF
[vps]
$VPS_IP ansible_user=$VPS_USER ansible_port=22
EOF

echo "[OK] Inventory actualizado."

# ============================================================
# RESULTADO
# ============================================================

echo
echo "========================================="
echo " Bootstrap completado correctamente"
echo "========================================="
echo
echo "[OK] Usuario: $VPS_USER"
echo "[OK] Clave SSH instalada en el servidor."
echo "[OK] Inventory configurado para $VPS_USER."
