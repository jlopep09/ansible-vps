#!/usr/bin/env bash

set -euo pipefail

ENV_FILE="./.env"
ANSIBLE_DIR="./ansible"
INVENTORY="$ANSIBLE_DIR/inventory.ini"
PLAYBOOK="$ANSIBLE_DIR/playbooks/user.yml"

# ------------------------------------------------------------
# Funciones
# ------------------------------------------------------------

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

# ------------------------------------------------------------
# Inicio
# ------------------------------------------------------------

echo "========================================="
echo " Configuración inicial del usuario VPS"
echo "========================================="
echo

# ------------------------------------------------------------
# Cargar .env
# ------------------------------------------------------------

load_env

require_variable "VPS_IP"
require_variable "VPS_USER"
require_variable "VPS_PASSWORD"
require_variable "SSH_PRIVATE_KEY"
require_variable "SSH_PUBLIC_KEY"

# ------------------------------------------------------------
# Comprobar archivos
# ------------------------------------------------------------

if [[ ! -f "$INVENTORY" ]]; then
    error "No existe el inventory de Ansible: $INVENTORY"
fi

if [[ ! -f "$PLAYBOOK" ]]; then
    error "No existe el playbook: $PLAYBOOK"
fi

if [[ ! -f "$SSH_PRIVATE_KEY" ]]; then
    error "No existe la clave privada: $SSH_PRIVATE_KEY"
fi

chmod 600 "$SSH_PRIVATE_KEY"

# ------------------------------------------------------------
# Ejecutar Ansible
# ------------------------------------------------------------

echo "[INFO] Creando usuario $VPS_USER en el VPS..."
echo

if ! ansible-playbook \
    "$PLAYBOOK" \
    -i "$INVENTORY" \
    -e "ansible_password=$VPS_PASSWORD"
then
    error "El playbook de creación del usuario ha fallado."
fi

echo
echo "[OK] Usuario $VPS_USER creado/configurado correctamente."

# ------------------------------------------------------------
# Comprobar acceso SSH con la nueva clave
# ------------------------------------------------------------

echo
echo "========================================="
echo " Comprobando acceso SSH"
echo "========================================="
echo

SSH_OUTPUT=""

if ! SSH_OUTPUT=$(
    ssh \
        -i "$SSH_PRIVATE_KEY" \
        -o BatchMode=yes \
        -o ConnectTimeout=10 \
        -o StrictHostKeyChecking=accept-new \
        "$VPS_USER@$VPS_IP" \
        "echo SSH_CONNECTION_OK" \
        2>&1
); then

    echo "$SSH_OUTPUT"

    error "No se ha podido acceder al VPS como $VPS_USER mediante la nueva clave SSH."
fi

echo "$SSH_OUTPUT"

if [[ "$SSH_OUTPUT" != *"SSH_CONNECTION_OK"* ]]; then
    error "La conexión SSH no ha devuelto la confirmación esperada."
fi

# ------------------------------------------------------------
# Resultado
# ------------------------------------------------------------

echo
echo "========================================="
echo " Bootstrap completado correctamente"
echo "========================================="
echo
echo "[OK] Usuario: $VPS_USER"
echo "[OK] Acceso SSH mediante clave verificado."
echo
