#!/usr/bin/env bash

set -euo pipefail

ENV_FILE="./.env"
PRIVATE_DIR="./private"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

mkdir -p "$PRIVATE_DIR"

# ============================================================
# FUNCIONES AUXILIARES
# ============================================================

print_header() {
    echo
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE} $1${NC}"
    echo -e "${BLUE}=========================================${NC}"
    echo
}

print_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

save_env_variable() {
    local variable="$1"
    local value="$2"

    touch "$ENV_FILE"
    chmod 600 "$ENV_FILE"

    if grep -q "^${variable}=" "$ENV_FILE" 2>/dev/null || false; then
        sed -i "s|^${variable}=.*|${variable}=${value}|" "$ENV_FILE"
    else
        printf '%s=%s\n' "$variable" "$value" >> "$ENV_FILE"
    fi
}

load_env() {
    if [[ -f "$ENV_FILE" ]]; then
        set -a
        # shellcheck disable=SC1090
        source "$ENV_FILE"
        set +a
    fi
}

# ============================================================
# PREGUNTAS INTERACTIVAS
# ============================================================

ask_vps_ip() {
    print_header "IP del Servidor VPS"
    
    echo "¿Cuál es la dirección IP de tu servidor VPS?"
    echo "Ejemplo: 192.168.1.100"
    echo
    
    read -rp "IP del VPS: " vps_ip
    
    if [[ -z "$vps_ip" ]]; then
        print_error "La IP no puede estar vacía"
        ask_vps_ip
        return
    fi
    
    print_success "IP configurada: $vps_ip"
    save_env_variable "VPS_IP" "$vps_ip"
}

ask_vps_password() {
    print_header "Contraseña Root del VPS"
    
    echo "Introduce la contraseña de root para el primer acceso al servidor."
    echo "Esta será usada solo para la configuración inicial."
    echo
    
    read -rp "Contraseña root: " vps_password
    echo
    
    if [[ -z "$vps_password" ]]; then
        print_error "La contraseña no puede estar vacía"
        ask_vps_password
        return
    fi
    
    print_success "Contraseña guardada"
    save_env_variable "VPS_PASSWORD" "$vps_password"
}

ask_username() {
    print_header "Usuario del VPS"
    
    echo "¿Qué nombre deseas para el usuario no-root en el VPS?"
    echo "Este usuario será creado si no existe."
    echo "Ejemplo: deploy, vpsadmin, etc."
    echo
    
    read -rp "Nombre de usuario: " vps_user
    
    if [[ -z "$vps_user" ]]; then
        print_error "El nombre de usuario no puede estar vacío"
        ask_username
        return
    fi
    
    if [[ ! "$vps_user" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
        print_error "Nombre de usuario inválido. Usa solo minúsculas, números, guiones y guiones bajos."
        ask_username
        return
    fi
    
    print_success "Usuario configurado: $vps_user"
    save_env_variable "VPS_USER" "$vps_user"
}

ask_ssh_key() {
    print_header "Configuración de Clave SSH"
    
    echo "¿Cómo deseas configurar la clave SSH para Ansible?"
    echo
    echo "  1) Usar una clave existente en ./private/"
    echo "  2) Generar una nueva clave (sin passphrase)"
    echo "  3) Cargar una clave existente con passphrase (desde archivo)"
    echo
    
    while true; do
        read -rp "Selecciona una opción [1/2/3]: " ssh_choice
        
        case "$ssh_choice" in
            1)
                ask_existing_key
                return 0
                ;;
            2)
                ask_generate_new_key
                return 0
                ;;
            3)
                ask_import_key_with_passphrase
                return 0
                ;;
            *)
                print_error "Opción no válida. Introduce 1, 2 o 3."
                ;;
        esac
    done
}

ask_existing_key() {
    echo
    echo "Claves disponibles en $PRIVATE_DIR:"
    echo
    
    if ! ls -1 "$PRIVATE_DIR" 2>/dev/null | grep -v '\.pub$' | grep -v ':Zone\.Identifier$' | head -5; then
        print_error "No hay claves privadas disponibles en $PRIVATE_DIR"
        ask_ssh_key
        return
    fi
    
    echo
    read -rp "Nombre de la clave (solo el nombre, sin ruta): " key_name
    
    key_name="${key_name##*/}"
    
    if [[ ! -f "$PRIVATE_DIR/$key_name" ]]; then
        print_error "No existe la clave: $PRIVATE_DIR/$key_name"
        ask_ssh_key
        return
    fi
    
    print_info "Configurando clave SSH..."
    configure_ssh_agent "$PRIVATE_DIR/$key_name"
    chmod 600 "$PRIVATE_DIR/$key_name"
    
    save_env_variable "SSH_KEY_NAME" "$key_name"
    save_env_variable "SSH_PRIVATE_KEY" "./private/$key_name"
    
    if [[ ! -f "$PRIVATE_DIR/$key_name.pub" ]]; then
        print_info "Generando clave pública..."
        ssh-keygen -y -f "$PRIVATE_DIR/$key_name" > "$PRIVATE_DIR/$key_name.pub"
        chmod 644 "$PRIVATE_DIR/$key_name.pub"
    fi
    
    save_env_variable "SSH_PUBLIC_KEY" "./private/$key_name.pub"
    save_env_variable "SSH_KEY_PASSPHRASE" "true"
    print_success "Clave configurada: $key_name"
}

ask_generate_new_key() {
    echo
    read -rp "Nombre para la nueva clave SSH: " key_name
    
    key_name="${key_name##*/}"
    
    if [[ -z "$key_name" ]]; then
        print_error "El nombre no puede estar vacío"
        ask_generate_new_key
        return
    fi
    
    if [[ -f "$PRIVATE_DIR/$key_name" ]]; then
        print_error "Ya existe una clave con ese nombre"
        ask_generate_new_key
        return
    fi
    
    print_info "Generando nueva clave ED25519 (sin passphrase)..."
    
    ssh-keygen \
        -t ed25519 \
        -f "$PRIVATE_DIR/$key_name" \
        -N "" \
        -C "ansible-vps" \
        -q
    
    chmod 600 "$PRIVATE_DIR/$key_name"
    chmod 644 "$PRIVATE_DIR/$key_name.pub"
    
    print_success "Clave SSH generada"
    
    save_env_variable "SSH_KEY_NAME" "$key_name"
    save_env_variable "SSH_PRIVATE_KEY" "./private/$key_name"
    save_env_variable "SSH_PUBLIC_KEY" "./private/$key_name.pub"
}

ask_import_key_with_passphrase() {
    echo
    read -rp "Ruta completa del archivo de clave privada: " key_path
    
    key_path="${key_path/#\~/$HOME}"
    
    if [[ ! -f "$key_path" ]]; then
        print_error "No existe el archivo: $key_path"
        ask_ssh_key
        return
    fi
    
    key_name=$(basename "$key_path")
    
    print_info "Copiando clave a $PRIVATE_DIR/$key_name..."
    cp "$key_path" "$PRIVATE_DIR/$key_name"
    chmod 600 "$PRIVATE_DIR/$key_name"
    
    # Si existe la clave pública, copiarla también
    if [[ -f "${key_path}.pub" ]]; then
        cp "${key_path}.pub" "$PRIVATE_DIR/$key_name.pub"
        chmod 644 "$PRIVATE_DIR/$key_name.pub"
    else
        print_info "Generando clave pública..."
        ssh-keygen -y -f "$PRIVATE_DIR/$key_name" > "$PRIVATE_DIR/$key_name.pub"
        chmod 644 "$PRIVATE_DIR/$key_name.pub"
    fi
    
    print_warning "La clave tiene passphrase. Configurando ssh-agent..."
    configure_ssh_agent "$PRIVATE_DIR/$key_name"
    
    save_env_variable "SSH_KEY_NAME" "$key_name"
    save_env_variable "SSH_PRIVATE_KEY" "./private/$key_name"
    save_env_variable "SSH_PUBLIC_KEY" "./private/$key_name.pub"
    save_env_variable "SSH_KEY_PASSPHRASE" "true"
}

configure_ssh_agent() {
    local key_path="$1"

    echo
    echo "Para usar una clave con passphrase, debes cargarla en ssh-agent."
    echo "Si la clave está protegida, la passphrase se pedirá aquí y se verá al escribirla."
    echo

    # Asegurar que el agente exista y que el entorno actual tenga SSH_AUTH_SOCK
    if [[ -z "${SSH_AUTH_SOCK:-}" ]] || [[ ! -S "${SSH_AUTH_SOCK}" ]]; then
        if [[ -f "$HOME/.ssh/agent-env" ]]; then
            # shellcheck disable=SC1090
            source "$HOME/.ssh/agent-env" > /dev/null 2>&1 || true
        fi
    fi

    if [[ -z "${SSH_AUTH_SOCK:-}" ]] || [[ ! -S "${SSH_AUTH_SOCK}" ]]; then
        print_info "Iniciando ssh-agent..."
        eval "$(ssh-agent -s)" > /dev/null
        export SSH_AUTH_SOCK
        export SSH_AGENT_PID

        mkdir -p "$HOME/.ssh"
        cat > "$HOME/.ssh/agent-env" <<EOF
export SSH_AGENT_PID=$SSH_AGENT_PID
export SSH_AUTH_SOCK=$SSH_AUTH_SOCK
EOF
        chmod 600 "$HOME/.ssh/agent-env"
    fi

    print_info "Agregando clave a ssh-agent..."

    if ! ssh-add "$key_path"; then
        print_error "No se pudo cargar la clave SSH en ssh-agent. Revisa la ruta y la passphrase."
        return 1
    fi

    if ! grep -q "SSH_AUTH_SOCK" ~/.bashrc 2>/dev/null; then
        echo "export SSH_AUTH_SOCK=\$SSH_AUTH_SOCK" >> ~/.bashrc
        print_info "Configuración de ssh-agent agregada a ~/.bashrc"
    fi

    print_success "Clave cargada en ssh-agent"
    save_env_variable "SSH_KEY_PASSPHRASE" "true"
}

ask_domain() {
    print_header "Dominio (Opcional)"
    
    echo "¿Deseas configurar un dominio para tu servidor?"
    echo "(Puedes dejarlo vacío si no tienes uno)"
    echo
    
    read -rp "Dominio (ejemplo: example.com): " domain
    
    if [[ -n "$domain" ]]; then
        print_success "Dominio configurado: $domain"
        save_env_variable "VPS_DOMAIN" "$domain"
    else
        print_info "Dominio omitido"
    fi
}

ask_email() {
    print_header "Email para certificados SSL (Opcional)"
    
    echo "¿Qué email deseas usar para certificados SSL (Let's Encrypt)?"
    echo "(Puedes dejarlo vacío por ahora)"
    echo
    
    read -rp "Email: " email
    
    if [[ -n "$email" ]]; then
        if [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            print_success "Email configurado: $email"
            save_env_variable "LETSENCRYPT_EMAIL" "$email"
        else
            print_error "Email inválido: $email"
            ask_email
        fi
    else
        print_info "Email omitido (puedes agregarlo después en .env)"
    fi
}

show_summary() {
    print_header "Resumen de Configuración"
    
    load_env
    
    echo "Los siguientes valores han sido guardados en $ENV_FILE:"
    echo
    echo "  VPS_IP:              ${VPS_IP:-[no configurada]}"
    echo "  VPS_USER:            ${VPS_USER:-[no configurada]}"
    echo "  SSH_KEY_NAME:        ${SSH_KEY_NAME:-[no configurada]}"
    echo "  VPS_DOMAIN:          ${VPS_DOMAIN:-[opcional]}"
    echo "  LETSENCRYPT_EMAIL:   ${LETSENCRYPT_EMAIL:-[opcional]}"
    echo
    echo -e "${YELLOW}Nota: La contraseña de root NO se muestra por seguridad${NC}"
    echo
}

# ============================================================
# MENÚ PRINCIPAL
# ============================================================

show_main_menu() {
    print_header "Configurador Automático de VPS"
    
    echo "¿Qué deseas hacer?"
    echo
    echo "  1) Realizar configuración inicial completa"
    echo "  2) Usar configuración existente (solo editar variables específicas)"
    echo "  3) Ver configuración actual"
    echo "  4) Limpiar configuración (.env)"
    echo "  0) Salir"
    echo
}

main() {
    while true; do
        show_main_menu
        read -rp "Selecciona una opción: " option
        
        case "$option" in
            1)
                print_header "Configuración Inicial"
                echo "Se te harán varias preguntas para configurar el VPS."
                echo "Las respuestas se guardarán en .env"
                echo
                read -rp "¿Deseas continuar? [s/n]: " confirm
                
                if [[ "$confirm" =~ ^[sS]$ ]]; then
                    ask_vps_ip
                    ask_vps_password
                    ask_username
                    ask_ssh_key
                    ask_domain
                    ask_email
                    
                    show_summary
                    
                    print_success "¡Configuración completada!"
                    echo
                    echo "Próximo paso: ejecuta './run.sh' para configurar el servidor"
                    echo
                fi
                ;;
                
            2)
                load_env
                
                if [[ -z "${VPS_IP:-}" ]]; then
                    print_error "No hay configuración previa. Ejecuta la opción 1 primero."
                else
                    print_header "Editar Configuración"
                    echo "¿Qué deseas editar?"
                    echo
                    echo "  1) IP del VPS"
                    echo "  2) Usuario del VPS"
                    echo "  3) Contraseña de root"
                    echo "  4) Clave SSH"
                    echo "  5) Dominio"
                    echo "  6) Email"
                    echo "  0) Volver"
                    echo
                    
                    read -rp "Selecciona: " edit_option
                    
                    case "$edit_option" in
                        1) ask_vps_ip ;;
                        2) ask_username ;;
                        3) ask_vps_password ;;
                        4) ask_ssh_key ;;
                        5) ask_domain ;;
                        6) ask_email ;;
                    esac
                fi
                ;;
                
            3)
                show_summary
                read -rp "Presiona Enter para continuar..."
                ;;
                
            4)
                read -rp "¿Estás seguro de que deseas limpiar .env? [s/n]: " confirm
                
                if [[ "$confirm" =~ ^[sS]$ ]]; then
                    rm -f "$ENV_FILE"
                    print_success "Archivo .env eliminado"
                fi
                ;;
                
            0)
                print_info "Saliendo..."
                exit 0
                ;;
                
            *)
                print_error "Opción no válida"
                ;;
        esac
        
        echo
    done
}

# ============================================================
# INICIO
# ============================================================

if [[ "${1:-}" == "--automated" ]]; then
    # Modo no interactivo para CI/CD
    load_env
    
    if [[ -z "${VPS_IP:-}" ]]; then
        print_error "VPS_IP no está configurada en .env"
        exit 1
    fi
    
    print_success "Configuración cargada desde .env"
    exit 0
else
    main
fi
