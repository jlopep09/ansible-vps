#!/usr/bin/env bash

set -euo pipefail

ENV_FILE="./.env"
ANSIBLE_DIR="./ansible"
INVENTORY_FILE="$ANSIBLE_DIR/inventory.ini"
PLAYBOOK="$ANSIBLE_DIR/playbooks/ssh.yml"

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

print_warning() {
    echo "[WARN] $1"
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
echo " Securización SSH del VPS"
echo "========================================="
echo

load_env

require_variable "VPS_IP"
require_variable "VPS_USER"
require_variable "SSH_PRIVATE_KEY"

# Comprobar archivos
if [[ ! -f "$PLAYBOOK" ]]; then
    error "No existe el playbook: $PLAYBOOK"
fi

if [[ ! -f "$SSH_PRIVATE_KEY" ]]; then
    error "No existe la clave privada: $SSH_PRIVATE_KEY"
fi

if [[ ! -f "$INVENTORY_FILE" ]]; then
    error "No existe el inventario: $INVENTORY_FILE"
fi

chmod 600 "$SSH_PRIVATE_KEY"

# ============================================================
# Configuración SSH segura
# ============================================================

echo "[INFO] Preparando la configuración SSH segura para $VPS_USER@$VPS_IP..."
echo

# Cargar la clave SSH con passphrase en el agente si hace falta.
init_ssh_agent
if ! ssh-add -l 2>/dev/null | grep -q "$(ssh-keygen -lf "$SSH_PRIVATE_KEY" 2>/dev/null | awk '{print $2}')"; then
    ssh-add "$SSH_PRIVATE_KEY" 2>/dev/null || true
fi

export SSH_AUTH_SOCK
export SSH_AGENT_PID

echo "[INFO] La clave SSH estará disponible para el acceso por clave pública."
echo

# ============================================================
# Ejecutar Ansible
# ============================================================

echo "[INFO] Ejecutando playbook de securización SSH..."
echo

cd "$ANSIBLE_DIR"

# Exportar variables de ssh-agent para que Ansible pueda usarlas
export SSH_AUTH_SOCK
export SSH_AGENT_PID

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
    error "El playbook de securización SSH ha fallado"
fi
