#!/usr/bin/env bash

set -euo pipefail

ENV_FILE="./.env"
ANSIBLE_DIR="./ansible"
INVENTORY="$ANSIBLE_DIR/inventory.ini"
PLAYBOOKS_DIR="$ANSIBLE_DIR/playbooks"

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

check_structure() {
    if [[ ! -d "$ANSIBLE_DIR" ]]; then
        error "No existe el directorio $ANSIBLE_DIR"
    fi

    if [[ ! -f "$INVENTORY" ]]; then
        error "No existe el inventario: $INVENTORY"
    fi

    if [[ ! -d "$PLAYBOOKS_DIR" ]]; then
        error "No existe el directorio: $PLAYBOOKS_DIR"
    fi
}

check_ssh_key() {
    if [[ ! -f "$SSH_PRIVATE_KEY" ]]; then
        error "No existe la clave privada: $SSH_PRIVATE_KEY"
    fi

    chmod 600 "$SSH_PRIVATE_KEY"
}

run_playbook() {
    local name="$1"
    local playbook="$2"

    echo
    echo "========================================="
    echo " Instalando: $name"
    echo "========================================="
    echo

    if [[ ! -f "$PLAYBOOKS_DIR/$playbook" ]]; then
        echo "[ERROR] No existe el playbook:"
        echo "        $PLAYBOOKS_DIR/$playbook"
        return 1
    fi

    ansible-playbook \
        -i "$INVENTORY" \
        --private-key "$SSH_PRIVATE_KEY" \
        "$PLAYBOOKS_DIR/$playbook"

    echo
    echo "[OK] $name instalado/configurado correctamente."

    return 0
}

show_menu() {
    echo
    echo "========================================="
    echo " Provisionamiento de servicios"
    echo "========================================="
    echo
    echo "1) Traefik"
    echo "0) Salir"
    echo
}

# ------------------------------------------------------------
# Inicio
# ------------------------------------------------------------

echo "========================================="
echo " Provisionamiento de servicios"
echo "========================================="
echo

load_env

# ------------------------------------------------------------
# Comprobar variables
# ------------------------------------------------------------

require_variable "VPS_IP"
require_variable "VPS_USER"
require_variable "SSH_PRIVATE_KEY"

# ------------------------------------------------------------
# Comprobar estructura
# ------------------------------------------------------------

check_structure
check_ssh_key

# ------------------------------------------------------------
# Mostrar configuración
# ------------------------------------------------------------

echo "[INFO] VPS:"
echo "       $VPS_USER@$VPS_IP"

echo
echo "[INFO] Clave SSH:"
echo "       $SSH_PRIVATE_KEY"

# ------------------------------------------------------------
# Menú
# ------------------------------------------------------------

while true; do

    show_menu

    read -rp "Selecciona una opción: " OPTION

    case "$OPTION" in

        1)
            run_playbook \
                "Traefik" \
                "traefik.yml"
            ;;

        0)
            echo
            echo "[OK] Provisionamiento finalizado."
            exit 0
            ;;

        *)
            echo
            echo "[ERROR] Opción no válida."
            echo "[INFO] Selecciona una opción del menú."
            ;;

    esac

done
