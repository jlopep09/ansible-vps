#!/usr/bin/env bash

set -euo pipefail

ENV_FILE="./.env"
ANSIBLE_DIR="./ansible"
INVENTORY_FILE="$ANSIBLE_DIR/inventory.ini"
PLAYBOOK="$ANSIBLE_DIR/playbooks/ssh.yml"

# ------------------------------------------------------------
# Funciones
# ------------------------------------------------------------

load_env() {
    if [[ ! -f "$ENV_FILE" ]]; then
        echo "[ERROR] No existe $ENV_FILE."
        exit 1
    fi

    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
}

require_variable() {
    local variable="$1"

    if [[ -z "${!variable:-}" ]]; then
        echo "[ERROR] Falta la variable $variable en $ENV_FILE."
        echo "[ERROR] Ejecuta primero los scripts de configuración inicial."
        exit 1
    fi
}

# ------------------------------------------------------------
# Inicio
# ------------------------------------------------------------

echo "========================================="
echo " Securización SSH del VPS"
echo "========================================="
echo

load_env

# ------------------------------------------------------------
# Comprobar variables necesarias
# ------------------------------------------------------------

require_variable "VPS_IP"
require_variable "VPS_USER"
require_variable "SSH_PRIVATE_KEY"

# ------------------------------------------------------------
# Comprobar archivos
# ------------------------------------------------------------

if [[ ! -f "$PLAYBOOK" ]]; then
    echo "[ERROR] No existe el playbook:"
    echo "        $PLAYBOOK"
    exit 1
fi

if [[ ! -f "$SSH_PRIVATE_KEY" ]]; then
    echo "[ERROR] No existe la clave privada:"
    echo "        $SSH_PRIVATE_KEY"
    exit 1
fi

if [[ ! -f "$INVENTORY_FILE" ]]; then
    echo "[ERROR] No existe el inventario:"
    echo "        $INVENTORY_FILE"
    exit 1
fi

# ------------------------------------------------------------
# Comprobar acceso antes de modificar SSH
# ------------------------------------------------------------

echo "[INFO] Comprobando acceso SSH como $VPS_USER@$VPS_IP..."

SSH_ERROR="$(mktemp)"

if ssh \
    -i "$SSH_PRIVATE_KEY" \
    -o BatchMode=yes \
    -o StrictHostKeyChecking=accept-new \
    -o UserKnownHostsFile="$HOME/.ssh/known_hosts" \
    -o ConnectTimeout=15 \
    -o LogLevel=ERROR \
    "$VPS_USER@$VPS_IP" \
    "exit" \
    2>"$SSH_ERROR"
then
    echo "[OK] Acceso SSH mediante clave confirmado."
    rm -f "$SSH_ERROR"
else
    echo "[ERROR] No se puede acceder al VPS mediante la clave SSH."
    echo
    echo "Detalle:"
    cat "$SSH_ERROR"
    rm -f "$SSH_ERROR"
    exit 1
fi

# ------------------------------------------------------------
# Ejecutar Ansible
# ------------------------------------------------------------

echo
echo "[INFO] Ejecutando playbook de securización SSH..."
echo

cd "$ANSIBLE_DIR"

if ansible-playbook \
    "playbooks/ssh.yml" \
    -i "inventory.ini" \
    --private-key "../$SSH_PRIVATE_KEY"
then

    echo
    echo "========================================="
    echo " SSH securizado correctamente"
    echo "========================================="
    echo
    echo "[OK] Root ya no podrá acceder mediante SSH."
    echo "[OK] La autenticación mediante contraseña ha sido desactivada."
    echo "[OK] El acceso continuará mediante:"
    echo
    echo "     $VPS_USER@$VPS_IP"
    echo

else

    echo
    echo "[ERROR] El playbook de securización SSH ha fallado."
    exit 1
fi
