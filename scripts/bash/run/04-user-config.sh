#!/usr/bin/env bash

set -euo pipefail

ENV_FILE="./.env"

# ------------------------------------------------------------
# Funciones
# ------------------------------------------------------------

load_env() {
    if [[ ! -f "$ENV_FILE" ]]; then
        return 0
    fi

    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
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

validate_username() {
    local username="$1"

    if [[ -z "$username" ]]; then
        echo "[ERROR] El nombre de usuario no puede estar vacío."
        return 1
    fi

    # Nombre de usuario Linux razonable:
    # - empieza por letra minúscula o _
    # - contiene letras minúsculas, números, _ o -
    # - máximo 32 caracteres
    if [[ ! "$username" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
        echo "[ERROR] El nombre de usuario no es válido."
        echo
        echo "Debe:"
        echo "  - empezar por una letra minúscula o '_'"
        echo "  - contener únicamente letras minúsculas, números, '_' o '-'"
        echo "  - tener como máximo 32 caracteres"
        return 1
    fi

    if [[ "$username" == "root" ]]; then
        echo "[ERROR] El usuario no puede llamarse root."
        return 1
    fi

    return 0
}

# ------------------------------------------------------------
# Inicio
# ------------------------------------------------------------

echo "========================================="
echo " Configuración del usuario VPS"
echo "========================================="
echo

# ------------------------------------------------------------
# Cargar configuración existente
# ------------------------------------------------------------

load_env

# ------------------------------------------------------------
# Utilizar usuario existente
# ------------------------------------------------------------

if [[ -n "${VPS_USER:-}" ]]; then

    echo "[INFO] Ya existe un usuario VPS configurado:"
    echo "[INFO] Usando automáticamente: $VPS_USER"

    if ! validate_username "$VPS_USER"; then
        echo
        echo "[ERROR] El usuario almacenado en .env no es válido."
        exit 1
    fi

else

    # --------------------------------------------------------
    # No existe usuario: preguntar
    # --------------------------------------------------------

    while true; do

        read -rp "Nombre del usuario que quieres crear en el VPS: " VPS_USER

        if validate_username "$VPS_USER"; then
            break
        fi

        echo
        echo "[INFO] Introduce otro nombre de usuario."
        echo

    done

    # --------------------------------------------------------
    # Guardar configuración
    # --------------------------------------------------------

    save_env_variable "VPS_USER" "$VPS_USER"

fi

# ------------------------------------------------------------
# Resultado
# ------------------------------------------------------------

echo
echo "========================================="
echo " Usuario configurado correctamente"
echo "========================================="
echo
echo "Usuario VPS: $VPS_USER"
echo "Configuración: $ENV_FILE"
echo
echo "[OK] Configuración guardada correctamente."