#!/usr/bin/env bash

set -euo pipefail

ENV_FILE="./.env"
ANSIBLE_DIR="./ansible"
INVENTORY_FILE="$ANSIBLE_DIR/inventory.ini"

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
        exit 1
    fi
}

run_playbook() {
    local playbook="$1"
    local description="$2"

    echo
    echo "========================================="
    echo " $description"
    echo "========================================="
    echo

    if [[ ! -f "$playbook" ]]; then
        echo "[ERROR] No existe el playbook:"
        echo "        $playbook"
        exit 1
    fi

    # Ejecutamos Ansible y capturamos la salida para poder detectar
    # también el caso en el que no se haya ejecutado ningún host.
    local output
    local exit_code

    set +e

    output="$(
        ansible-playbook \
            "$playbook" \
            -i "$INVENTORY_FILE" \
            --private-key "$SSH_PRIVATE_KEY_ABSOLUTE" \
            2>&1
    )"

    exit_code=$?

    set -e

    echo "$output"

    if [[ $exit_code -ne 0 ]]; then
        echo
        echo "[ERROR] $description ha fallado."
        echo "[ERROR] Código de salida de Ansible: $exit_code"
        exit "$exit_code"
    fi

    # Detectar errores de inventario.
    if echo "$output" | grep -q "Unable to parse .*inventory"; then
        echo
        echo "[ERROR] Ansible no ha podido cargar el inventario."
        echo "[ERROR] Revisa:"
        echo "        $INVENTORY_FILE"
        exit 1
    fi

    # Detectar que no se ejecutó ningún host.
    if echo "$output" | grep -q "Could not match supplied host pattern"; then
        echo
        echo "[ERROR] Ansible no encontró ningún host válido en el inventario."
        echo "[ERROR] Inventario:"
        echo "        $INVENTORY_FILE"
        exit 1
    fi

    if echo "$output" | grep -q "skipping: no hosts matched"; then
        echo
        echo "[ERROR] El playbook no se ha ejecutado sobre ningún host."
        echo "[ERROR] Revisa el inventario:"
        echo "        $INVENTORY_FILE"
        exit 1
    fi

    echo
    echo "[OK] $description completado correctamente."
}

# ------------------------------------------------------------
# Inicio
# ------------------------------------------------------------

echo "========================================="
echo " Configuración base del VPS"
echo "========================================="
echo

load_env

# ------------------------------------------------------------
# Variables necesarias
# ------------------------------------------------------------

require_variable "VPS_IP"
require_variable "VPS_USER"
require_variable "SSH_PRIVATE_KEY"

# ------------------------------------------------------------
# Comprobar Ansible
# ------------------------------------------------------------

if ! command -v ansible-playbook >/dev/null 2>&1; then
    echo "[ERROR] Ansible no está instalado."
    exit 1
fi

# ------------------------------------------------------------
# Comprobar directorios y archivos
# ------------------------------------------------------------

if [[ ! -d "$ANSIBLE_DIR" ]]; then
    echo "[ERROR] No existe el directorio:"
    echo "        $ANSIBLE_DIR"
    exit 1
fi

if [[ ! -f "$INVENTORY_FILE" ]]; then
    echo "[ERROR] No existe el inventario:"
    echo "        $INVENTORY_FILE"
    exit 1
fi

if [[ ! -f "$SSH_PRIVATE_KEY" ]]; then
    echo "[ERROR] No existe la clave privada:"
    echo "        $SSH_PRIVATE_KEY"
    exit 1
fi

# ------------------------------------------------------------
# Convertir la clave a ruta absoluta
# ------------------------------------------------------------

SSH_PRIVATE_KEY_ABSOLUTE="$(realpath "$SSH_PRIVATE_KEY")"

# ------------------------------------------------------------
# Convertir inventario a ruta absoluta
# ------------------------------------------------------------

INVENTORY_FILE_ABSOLUTE="$(realpath "$INVENTORY_FILE")"

# ------------------------------------------------------------
# Comprobar acceso SSH
# ------------------------------------------------------------

echo "[INFO] Comprobando acceso SSH como $VPS_USER@$VPS_IP..."

SSH_ERROR="$(mktemp)"

if ssh \
    -i "$SSH_PRIVATE_KEY_ABSOLUTE" \
    -o BatchMode=yes \
    -o StrictHostKeyChecking=accept-new \
    -o UserKnownHostsFile="$HOME/.ssh/known_hosts" \
    -o ConnectTimeout=15 \
    -o LogLevel=ERROR \
    "$VPS_USER@$VPS_IP" \
    "exit" \
    2>"$SSH_ERROR"
then
    echo "[OK] Acceso SSH confirmado."
    rm -f "$SSH_ERROR"
else
    echo "[ERROR] No se puede acceder al VPS mediante SSH."
    echo
    echo "Detalle:"
    cat "$SSH_ERROR"
    rm -f "$SSH_ERROR"
    exit 1
fi

# ------------------------------------------------------------
# Mostrar inventario utilizado
# ------------------------------------------------------------

echo
echo "[INFO] Inventario Ansible:"
echo "       $INVENTORY_FILE_ABSOLUTE"

# ------------------------------------------------------------
# Ejecutar playbooks
# ------------------------------------------------------------

run_playbook \
    "$ANSIBLE_DIR/playbooks/dependencies.yml" \
    "Instalación de dependencias"

run_playbook \
    "$ANSIBLE_DIR/playbooks/firewall.yml" \
    "Configuración del firewall"

run_playbook \
    "$ANSIBLE_DIR/playbooks/docker.yml" \
    "Instalación y configuración de Docker"

# ------------------------------------------------------------
# Resultado
# ------------------------------------------------------------

echo
echo "========================================="
echo " Configuración base completada"
echo "========================================="
echo
echo "[OK] Dependencias instaladas."
echo "[OK] Firewall configurado."
echo "[OK] Docker instalado y ejecutándose."
echo
