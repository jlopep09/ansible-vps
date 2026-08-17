#!/usr/bin/env bash

set -euo pipefail

ENV_FILE="./.env"
ANSIBLE_DIR="./ansible"
GROUP_VARS_DIR="$ANSIBLE_DIR/group_vars"

# ------------------------------------------------------------
# Funciones
# ------------------------------------------------------------

error() {
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

# ------------------------------------------------------------
# Inicio
# ------------------------------------------------------------

echo "========================================="
echo " Generación de variables de Ansible"
echo "========================================="
echo

load_env

# ------------------------------------------------------------
# Comprobar variables necesarias
# ------------------------------------------------------------

require_variable "VPS_IP"
require_variable "VPS_USER"
require_variable "SSH_PUBLIC_KEY"
require_variable "SSH_PRIVATE_KEY"

# ------------------------------------------------------------
# Comprobar estructura
# ------------------------------------------------------------

if [[ ! -d "$ANSIBLE_DIR" ]]; then
    error "No existe el directorio $ANSIBLE_DIR"
fi

mkdir -p "$GROUP_VARS_DIR"

# ------------------------------------------------------------
# Comprobar clave pública
# ------------------------------------------------------------

if [[ ! -f "$SSH_PUBLIC_KEY" ]]; then
    error "No existe la clave pública: $SSH_PUBLIC_KEY"
fi

SSH_PUBLIC_KEY_CONTENT="$(cat "$SSH_PUBLIC_KEY")"

if [[ -z "$SSH_PUBLIC_KEY_CONTENT" ]]; then
    error "La clave pública está vacía: $SSH_PUBLIC_KEY"
fi

# ------------------------------------------------------------
# Generar inventory.ini
# ------------------------------------------------------------

echo "[INFO] Generando $ANSIBLE_DIR/inventory.ini..."

cat > "$ANSIBLE_DIR/inventory.ini" <<EOF
[vps]
$VPS_IP ansible_user=$VPS_USER ansible_port=22
EOF

# ------------------------------------------------------------
# Generar group_vars/user.yml
# ------------------------------------------------------------

echo "[INFO] Generando $GROUP_VARS_DIR/user.yml..."

cat > "$GROUP_VARS_DIR/user.yml" <<EOF
---
# Generado automáticamente desde .env

username: "$VPS_USER"

ssh_public_key: "$SSH_PUBLIC_KEY_CONTENT"
EOF

# ------------------------------------------------------------
# Resultado
# ------------------------------------------------------------

echo
echo "========================================="
echo " Variables de Ansible generadas"
echo "========================================="
echo
echo "Inventory:"
echo "  $ANSIBLE_DIR/inventory.ini"
echo
echo "Variables:"
echo "  $GROUP_VARS_DIR/user.yml"
echo
echo "Usuario VPS:"
echo "  $VPS_USER"
echo
echo "IP VPS:"
echo "  $VPS_IP"
echo
echo "Clave pública:"
echo "  $SSH_PUBLIC_KEY"
echo
echo "[OK] Generación completada correctamente."
