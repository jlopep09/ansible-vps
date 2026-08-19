#!/usr/bin/env bash

set -euo pipefail

ENV_FILE="./.env"
PRIVATE_DIR="./private"

mkdir -p "$PRIVATE_DIR"

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

normalize_key_name() {
    local name="$1"

    # Solo utilizamos el nombre del archivo.
    name="${name##*/}"

    printf '%s' "$name"
}

key_exists() {
    local key_name="$1"

    [[ -f "$PRIVATE_DIR/$key_name" ]]
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

save_ssh_configuration() {
    local key_name="$1"
    local key_path="$PRIVATE_DIR/$key_name"
    local public_key_path="${key_path}.pub"

    if [[ ! -f "$key_path" ]]; then
        echo "[ERROR] La clave privada no existe: $key_path"
        return 1
    fi

    if [[ ! -f "$public_key_path" ]]; then
        generate_public_key "$key_path" "$public_key_path"
    fi

    local derived_public_key
    derived_public_key="$(ssh-keygen -y -f "$key_path" 2>/dev/null || true)"
    local stored_public_key
    stored_public_key="$(cat "$public_key_path")"

    if [[ -n "$derived_public_key" && "$derived_public_key" != "$stored_public_key" ]]; then
        echo "[WARN] La clave pública no coincidía con la privada. Se regenerará automáticamente."
        rm -f "$public_key_path"
        generate_public_key "$key_path" "$public_key_path"
    fi

    save_env_variable "SSH_KEY_NAME" "$key_name"
    save_env_variable "SSH_PRIVATE_KEY" "./private/$key_name"
    save_env_variable "SSH_PUBLIC_KEY" "./private/$key_name.pub"
}

generate_public_key() {
    local key_path="$1"
    local public_key_path="$2"

    echo "[INFO] Generando clave pública a partir de la privada..."

    ssh-keygen \
        -y \
        -f "$key_path" \
        > "$public_key_path"

    chmod 644 "$public_key_path"

    echo "[OK] Clave pública generada correctamente."
}

generate_key() {
    local key_name="$1"
    local key_path="$PRIVATE_DIR/$key_name"

    echo
    echo "[INFO] Generando nueva clave SSH ED25519..."
    echo "[INFO] Clave privada: $key_path"

    ssh-keygen \
        -t ed25519 \
        -f "$key_path" \
        -N "" \
        -C "ansible-vps"

    chmod 600 "$key_path"

    generate_public_key \
        "$key_path" \
        "${key_path}.pub"

    echo
    echo "[OK] Clave SSH generada correctamente."
}

ask_existing_key() {
    while true; do
        echo
        read -rp "Introduce el nombre de una clave existente en $PRIVATE_DIR: " KEY_NAME

        if [[ -z "$KEY_NAME" ]]; then
            echo "[ERROR] Debes introducir un nombre."
            continue
        fi

        KEY_NAME="$(normalize_key_name "$KEY_NAME")"

        if key_exists "$KEY_NAME"; then
            echo "[OK] Clave encontrada: $PRIVATE_DIR/$KEY_NAME"
            return 0
        fi

        echo "[ERROR] No existe: $PRIVATE_DIR/$KEY_NAME"
    done
}

generate_new_key() {
    while true; do
        echo
        read -rp "Nombre para la nueva clave: " KEY_NAME

        if [[ -z "$KEY_NAME" ]]; then
            echo "[ERROR] El nombre no puede estar vacío."
            continue
        fi

        KEY_NAME="$(normalize_key_name "$KEY_NAME")"

        if key_exists "$KEY_NAME"; then
            echo "[ERROR] Ya existe una clave privada con ese nombre:"
            echo "        $PRIVATE_DIR/$KEY_NAME"
            echo
            echo "[INFO] Introduce otro nombre."
            continue
        fi

        generate_key "$KEY_NAME"
        return 0
    done
}

# ------------------------------------------------------------
# Inicio
# ------------------------------------------------------------

echo "========================================="
echo " Configuración de clave SSH"
echo "========================================="
echo

if ! command -v ssh-keygen >/dev/null 2>&1; then
    echo "[ERROR] ssh-keygen no está instalado."
    echo "[ERROR] Instala openssh-client."
    exit 1
fi

# ------------------------------------------------------------
# Cargar configuración existente
# ------------------------------------------------------------

load_env

# ------------------------------------------------------------
# Usar configuración existente si es válida
# ------------------------------------------------------------

if [[ -n "${SSH_KEY_NAME:-}" ]]; then

    CONFIGURED_KEY_NAME="$(normalize_key_name "$SSH_KEY_NAME")"
    CONFIGURED_KEY_PATH="$PRIVATE_DIR/$CONFIGURED_KEY_NAME"
    CONFIGURED_PUBLIC_KEY_PATH="${CONFIGURED_KEY_PATH}.pub"

    if [[ -f "$CONFIGURED_KEY_PATH" ]]; then

        echo "[INFO] Ya existe una clave SSH configurada."
        echo "[INFO] Usando automáticamente: $CONFIGURED_KEY_NAME"

        KEY_NAME="$CONFIGURED_KEY_NAME"

        # Si falta la pública, regenerarla automáticamente.
        if [[ ! -f "$CONFIGURED_PUBLIC_KEY_PATH" ]]; then
            echo "[WARN] No existe la clave pública."
            generate_public_key \
                "$CONFIGURED_KEY_PATH" \
                "$CONFIGURED_PUBLIC_KEY_PATH"
        fi

    else

        echo "[WARN] La clave configurada en .env no existe:"
        echo "       $CONFIGURED_KEY_PATH"
        echo
        echo "[INFO] Será necesario seleccionar otra clave."

        KEY_NAME=""

        while [[ -z "$KEY_NAME" ]]; do

            read -rp "Nombre de la clave SSH que quieres utilizar: " KEY_NAME

            if [[ -z "$KEY_NAME" ]]; then
                echo "[ERROR] Debes introducir un nombre."
                continue
            fi

            KEY_NAME="$(normalize_key_name "$KEY_NAME")"

            if key_exists "$KEY_NAME"; then
                echo "[OK] Clave encontrada: $PRIVATE_DIR/$KEY_NAME"
                break
            fi

            echo
            echo "[WARN] No se ha encontrado:"
            echo "       $PRIVATE_DIR/$KEY_NAME"

            while true; do

                read -rp "¿Quieres generar una nueva clave ED25519? [S/n]: " ANSWER

                case "${ANSWER,,}" in

                    ""|s|si|sí|y|yes)
                        generate_new_key
                        break 2
                        ;;

                    n|no)
                        KEY_NAME=""
                        ask_existing_key
                        break 2
                        ;;

                    *)
                        echo "[ERROR] Respuesta no válida. Introduce 's' o 'n'."
                        ;;

                esac

            done
        done
    fi

else

    # --------------------------------------------------------
    # No existe configuración: flujo interactivo original
    # --------------------------------------------------------

    KEY_NAME=""

    read -rp "Nombre de la clave SSH que quieres utilizar: " KEY_NAME

    if [[ -n "$KEY_NAME" ]]; then

        KEY_NAME="$(normalize_key_name "$KEY_NAME")"

        if key_exists "$KEY_NAME"; then

            echo
            echo "[OK] Clave encontrada: $PRIVATE_DIR/$KEY_NAME"

        else

            echo
            echo "[WARN] No se ha encontrado:"
            echo "       $PRIVATE_DIR/$KEY_NAME"

            while true; do

                read -rp "¿Quieres generar una nueva clave ED25519? [S/n]: " ANSWER

                case "${ANSWER,,}" in

                    ""|s|si|sí|y|yes)
                        generate_new_key
                        break
                        ;;

                    n|no)
                        ask_existing_key
                        break
                        ;;

                    *)
                        echo "[ERROR] Respuesta no válida. Introduce 's' o 'n'."
                        ;;

                esac

            done
        fi

    else

        echo
        echo "[WARN] No has introducido ningún nombre de clave."

        while true; do

            read -rp "¿Quieres generar una nueva clave ED25519? [S/n]: " ANSWER

            case "${ANSWER,,}" in

                ""|s|si|sí|y|yes)
                    generate_new_key
                    break
                    ;;

                n|no)
                    ask_existing_key
                    break
                    ;;

                *)
                    echo "[ERROR] Respuesta no válida. Introduce 's' o 'n'."
                    ;;

            esac

        done
    fi
fi

# ------------------------------------------------------------
# Preparar rutas
# ------------------------------------------------------------

KEY_PATH="$PRIVATE_DIR/$KEY_NAME"
PUBLIC_KEY_PATH="${KEY_PATH}.pub"

if [[ ! -f "$KEY_PATH" ]]; then
    echo "[ERROR] No existe la clave privada:"
    echo "        $KEY_PATH"
    exit 1
fi

if [[ ! -f "$PUBLIC_KEY_PATH" ]]; then
    generate_public_key \
        "$KEY_PATH" \
        "$PUBLIC_KEY_PATH"
fi

chmod 600 "$KEY_PATH"
chmod 644 "$PUBLIC_KEY_PATH"

# ------------------------------------------------------------
# Guardar configuración
# ------------------------------------------------------------

save_ssh_configuration "$KEY_NAME"

# ------------------------------------------------------------
# Resultado
# ------------------------------------------------------------

echo
echo "========================================="
echo " Clave SSH configurada correctamente"
echo "========================================="
echo
echo "Nombre:          $KEY_NAME"
echo "Clave privada:   $KEY_PATH"
echo "Clave pública:   $PUBLIC_KEY_PATH"
echo "Configuración:   $ENV_FILE"
echo
echo "[OK] Configuración guardada correctamente."