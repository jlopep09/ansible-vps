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
require_variable "SSH_PRIVATE_KEY"

# ------------------------------------------------------------
# Comprobar estructura
# ------------------------------------------------------------

if [[ ! -d "$ANSIBLE_DIR" ]]; then
    error "No existe el directorio $ANSIBLE_DIR"
fi

mkdir -p "$GROUP_VARS_DIR"

# Si la clave pública no existe o no coincide, regenerarla desde la privada.
# Para claves con passphrase, se requiere que ya esté cargada en ssh-agent.
SSH_PUBLIC_KEY="${SSH_PUBLIC_KEY:-$(dirname "$SSH_PRIVATE_KEY")/$(basename "$SSH_PRIVATE_KEY").pub}"

if [[ -f "$SSH_PRIVATE_KEY" ]]; then
    if [[ -f "$HOME/.ssh/agent-env" ]]; then
        # shellcheck disable=SC1090
        source "$HOME/.ssh/agent-env" > /dev/null 2>&1 || true
    fi

    if [[ -n "${SSH_AUTH_SOCK:-}" ]] && [[ -S "${SSH_AUTH_SOCK}" ]] && ! ssh-add -l 2>/dev/null | grep -q "$(ssh-keygen -lf "$SSH_PRIVATE_KEY" 2>/dev/null | awk '{print $2}')"; then
        echo "[INFO] Cargando la clave SSH con passphrase en ssh-agent antes de generar variables..."
        ssh-add "$SSH_PRIVATE_KEY" >/dev/null 2>&1 || true
    else
        if ! ssh-add -l 2>/dev/null | grep -q "$(ssh-keygen -lf "$SSH_PRIVATE_KEY" 2>/dev/null | awk '{print $2}')"; then
            echo "[INFO] La clave privada tiene passphrase o no está cargada. Cargando ahora..."
            ssh-add "$SSH_PRIVATE_KEY" >/dev/null 2>&1 || true
        fi
    fi

    DERIVED_PUBLIC_KEY="$(ssh-keygen -y -f "$SSH_PRIVATE_KEY" 2>/dev/null || true)"

    if [[ -n "$DERIVED_PUBLIC_KEY" ]]; then
        if [[ ! -f "$SSH_PUBLIC_KEY" ]] || [[ "$(cat "$SSH_PUBLIC_KEY" 2>/dev/null || true)" != "$DERIVED_PUBLIC_KEY" ]]; then
            printf '%s\n' "$DERIVED_PUBLIC_KEY" > "$SSH_PUBLIC_KEY"
            chmod 644 "$SSH_PUBLIC_KEY"
        fi
    elif [[ -n "${SSH_KEY_PASSPHRASE:-}" ]] && [[ "${SSH_KEY_PASSPHRASE}" == "true" ]]; then
        echo "[WARN] La clave privada está protegida por passphrase y no está disponible en ssh-agent."
        echo "[WARN] Cárgala con: ssh-add $SSH_PRIVATE_KEY"
    fi
fi

if [[ ! -f "$SSH_PUBLIC_KEY" ]]; then
    error "No existe la clave pública: $SSH_PUBLIC_KEY"
fi

SSH_PUBLIC_KEY_CONTENT="$(cat "$SSH_PUBLIC_KEY")"

if [[ -z "$SSH_PUBLIC_KEY_CONTENT" ]]; then
    error "La clave pública está vacía: $SSH_PUBLIC_KEY"
fi

# Persistir siempre la ruta correcta en .env para evitar que se quede desalineada
if grep -q '^SSH_PUBLIC_KEY=' "$ENV_FILE" 2>/dev/null; then
    sed -i "s|^SSH_PUBLIC_KEY=.*|SSH_PUBLIC_KEY=${SSH_PUBLIC_KEY}|" "$ENV_FILE"
else
    printf '%s=%s\n' "SSH_PUBLIC_KEY" "$SSH_PUBLIC_KEY" >> "$ENV_FILE"
fi

if grep -q '^SSH_PRIVATE_KEY=' "$ENV_FILE" 2>/dev/null; then
    sed -i "s|^SSH_PRIVATE_KEY=.*|SSH_PRIVATE_KEY=${SSH_PRIVATE_KEY}|" "$ENV_FILE"
else
    printf '%s=%s\n' "SSH_PRIVATE_KEY" "$SSH_PRIVATE_KEY" >> "$ENV_FILE"
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
