#!/usr/bin/env bash

set -euo pipefail

ENV_FILE="./.env"

# ------------------------------------------------------------
# Colores
# ------------------------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ------------------------------------------------------------
# Funciones
# ------------------------------------------------------------

load_env() {
    if [[ -f "$ENV_FILE" ]]; then
        set -a
        # shellcheck disable=SC1090
        source "$ENV_FILE"
        set +a
    fi
}

run_script() {
    local script="$1"

    echo
    echo "========================================="
    echo " Ejecutando: $script"
    echo "========================================="
    echo

    if [[ ! -f "./scripts/$script" ]]; then
        echo -e "${RED}[ERROR] No existe ./scripts/$script${NC}"
        exit 1
    fi

    if [[ ! -x "./scripts/$script" ]]; then
        echo "[INFO] Añadiendo permisos de ejecución..."
        chmod +x "./scripts/$script"
    fi

    if "./scripts/$script"; then
        echo
        echo -e "${GREEN}[OK] Finalizado: $script${NC}"
    else
        echo
        echo -e "${RED}[ERROR] Falló: $script${NC}"
        exit 1
    fi
}

ask_execution_mode() {

    echo "========================================="
    echo " Modo de ejecución"
    echo "========================================="
    echo

    echo "¿Qué quieres hacer?"
    echo
    echo "  1) Ejecutar configuración inicial completa"
    echo "     (root + contraseña + creación de usuario + securización SSH)"
    echo
    echo "  2) Saltar configuración inicial"
    echo "     (usar usuario + clave SSH ya configurados)"
    echo

    while true; do
        read -rp "Selecciona una opción [1/2]: " OPTION

        case "$OPTION" in
            1)
                EXECUTION_MODE="full"
                return 0
                ;;

            2)
                EXECUTION_MODE="continue"
                return 0
                ;;

            *)
                echo "[ERROR] Opción no válida. Introduce 1 o 2."
                ;;
        esac
    done
}

# ------------------------------------------------------------
# Inicio
# ------------------------------------------------------------

echo
echo "========================================="
echo " Automatic VPS"
echo "========================================="
echo

load_env

# ------------------------------------------------------------
# Comprobar si ya existe configuración
# ------------------------------------------------------------

if [[ -n "${VPS_USER:-}" ]] &&
   [[ -n "${SSH_PRIVATE_KEY:-}" ]] &&
   [[ -f "$SSH_PRIVATE_KEY" ]]; then

    echo "[INFO] Se ha detectado una configuración VPS existente."
    echo
    echo "Usuario: $VPS_USER"
    echo "Clave:   $SSH_PRIVATE_KEY"
    echo "IP:      ${VPS_IP:-no configurada}"
    echo

    ask_execution_mode

else

    echo "[INFO] No se ha encontrado una configuración VPS completa."
    echo "[INFO] Se ejecutará la configuración inicial."
    echo

    EXECUTION_MODE="full"
fi

# ============================================================
# CONFIGURACIÓN INICIAL
# ============================================================

if [[ "$EXECUTION_MODE" == "full" ]]; then

    run_script "check-deps.sh"

    run_script "first-vps-login.sh"

    run_script "ssh-key.sh"

    run_script "user-config.sh"

    run_script "generate-ansible-vars.sh"

    run_script "bootstrap-user.sh"

    run_script "secure-ssh.sh"

fi

# ============================================================
# CONFIGURACIÓN POSTERIOR
# ============================================================

run_script "setup-base.sh"

# ------------------------------------------------------------
# Final
# ------------------------------------------------------------

echo
echo "========================================="
echo -e "${GREEN} Proceso completado correctamente${NC}"
echo "========================================="
echo
