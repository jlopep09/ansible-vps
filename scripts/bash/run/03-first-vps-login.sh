#!/usr/bin/env bash

set -euo pipefail

ENV_FILE="./.env"

# ------------------------------------------------------------
# Funciones
# ------------------------------------------------------------

error() {
    echo
    echo "[ERROR] $1"
    exit 1
}

save_env_variable() {
    local variable="$1"
    local value="$2"

    touch "$ENV_FILE"
    chmod 600 "$ENV_FILE"

    if grep -q "^${variable}=" "$ENV_FILE"; then
        sed -i "s|^${variable}=.*|${variable}=${value}|" "$ENV_FILE"
    else
        printf '%s=%s\n' "$variable" "$value" >> "$ENV_FILE"
    fi
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
echo " Primer acceso al VPS"
echo "========================================="
echo

load_env

require_variable "VPS_IP"
require_variable "VPS_PASSWORD"

# El primer acceso SIEMPRE es como root.
VPS_ROOT_USER="root"

# ------------------------------------------------------------
# Comprobar sshpass
# ------------------------------------------------------------

if ! command -v sshpass >/dev/null 2>&1; then
    error "sshpass no está instalado."
fi

# ------------------------------------------------------------
# Preparar temporal para errores
# ------------------------------------------------------------

TMP_ERROR=$(mktemp)

trap 'rm -f "$TMP_ERROR"' EXIT

# ------------------------------------------------------------
# Conexión SSH
# ------------------------------------------------------------

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
ssh-keygen -f "$HOME/.ssh/known_hosts" -R "$VPS_IP" 2>/dev/null || true

echo "[INFO] Conectando a ${VPS_ROOT_USER}@${VPS_IP}..."

set +e

sshpass -p "$VPS_PASSWORD" \
    ssh \
        -o StrictHostKeyChecking=accept-new \
        -o UserKnownHostsFile="$HOME/.ssh/known_hosts" \
        -o ConnectTimeout=15 \
        -o LogLevel=ERROR \
        "${VPS_ROOT_USER}@${VPS_IP}" \
        "exit" \
        2>"$TMP_ERROR"

SSH_EXIT_CODE=$?

set -e

if [[ $SSH_EXIT_CODE -ne 0 ]] && grep -Eq 'REMOTE HOST IDENTIFICATION HAS CHANGED|Host key verification failed' "$TMP_ERROR"; then
    read -rp "Se detectó un cambio de host key para $VPS_IP. ¿Quieres eliminarlo de ~/.ssh/known_hosts y reintentar? [s/n]: " retry_hostkey
    if [[ "$retry_hostkey" =~ ^[sS]$ ]]; then
        ssh-keygen -f "$HOME/.ssh/known_hosts" -R "$VPS_IP" 2>/dev/null || true

        set +e
        sshpass -p "$VPS_PASSWORD" \
            ssh \
                -o StrictHostKeyChecking=accept-new \
                -o UserKnownHostsFile="$HOME/.ssh/known_hosts" \
                -o ConnectTimeout=15 \
                -o LogLevel=ERROR \
                "${VPS_ROOT_USER}@${VPS_IP}" \
                "exit" \
                2>"$TMP_ERROR"
        SSH_EXIT_CODE=$?
        set -e
    fi
fi

# ------------------------------------------------------------
# Resultado
# ------------------------------------------------------------

if [[ $SSH_EXIT_CODE -eq 0 ]]; then

    echo "[OK] Conexión SSH como root realizada correctamente."
    echo "[OK] Fingerprint aceptado."
    echo "[OK] Variables guardadas en ${ENV_FILE}."
    echo "[OK] Script finalizado exitosamente."

    exit 0

else

    echo "[ERROR] Falló la conexión SSH como root."
    echo
    echo "Detalle:"
    cat "$TMP_ERROR"

    exit "$SSH_EXIT_CODE"
fi
