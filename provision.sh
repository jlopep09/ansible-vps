#!/usr/bin/env bash

set -euo pipefail

ENV_FILE="./.env"
ANSIBLE_DIR="./ansible"
INVENTORY="$ANSIBLE_DIR/inventory.ini"
PLAYBOOKS_DIR="$ANSIBLE_DIR/playbooks"

# ============================================================
# COLORES
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================
# FUNCIONES
# ============================================================

error() {
    echo
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

print_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_header() {
    echo
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE} $1${NC}"
    echo -e "${BLUE}=========================================${NC}"
    echo
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

save_env_variable() {
    local variable="$1"
    local value="$2"

    touch "$ENV_FILE"
    chmod 600 "$ENV_FILE"

    if grep -q "^${variable}=" "$ENV_FILE" 2>/dev/null; then
        sed -i "s|^${variable}=.*|${variable}=${value}|" "$ENV_FILE"
    else
        printf '%s=%s\n' "$variable" "$value" >> "$ENV_FILE"
    fi

    export "${variable}=${value}"
}

ask_yes_no() {
    local prompt="$1"

    while true; do
        read -rp "$prompt [s/N]: " answer

        case "${answer,,}" in
            s|si|sí|y|yes)
                return 0
                ;;
            ""|n|no)
                return 1
                ;;
            *)
                print_warning "Respuesta no válida. Introduce 's' o 'n'."
                ;;
        esac
    done
}

ensure_ghcr_variables() {
    local updated="false"

    if [[ -z "${GHCR_REGISTRY:-}" ]]; then
        GHCR_REGISTRY="ghcr.io"
        save_env_variable "GHCR_REGISTRY" "$GHCR_REGISTRY"
        updated="true"
        print_info "GHCR_REGISTRY no estaba definida. Se usará ghcr.io"
    fi

    if [[ -z "${GHCR_USERNAME:-}" ]]; then
        read -rp "Usuario de GitHub para GHCR (GHCR_USERNAME): " GHCR_USERNAME
        if [[ -z "${GHCR_USERNAME}" ]]; then
            error "GHCR_USERNAME es obligatoria para iniciar sesión en GHCR"
        fi
        save_env_variable "GHCR_USERNAME" "$GHCR_USERNAME"
        updated="true"
    fi

    if [[ -z "${GHCR_TOKEN:-}" ]]; then
        echo
        read -rsp "Token de GitHub para GHCR (GHCR_TOKEN): " GHCR_TOKEN
        echo
        if [[ -z "${GHCR_TOKEN}" ]]; then
            error "GHCR_TOKEN es obligatoria para iniciar sesión en GHCR"
        fi
        save_env_variable "GHCR_TOKEN" "$GHCR_TOKEN"
        updated="true"
    fi

    if [[ "$updated" == "true" ]]; then
        print_success "Variables de GHCR guardadas en $ENV_FILE"
    else
        print_info "Variables GHCR ya presentes en $ENV_FILE"
    fi
}

docker_post_install_flow() {
    if ask_yes_no "¿Deseas iniciar sesión en GHCR para usar imágenes privadas?"; then
        ensure_ghcr_variables
        run_playbook "Login en GHCR" "ghcr-login.yml"
    else
        print_info "Se omitió el login en GHCR"
    fi
}

require_variable() {
    local variable="$1"
    local description="${2:-$variable}"

    if [[ -z "${!variable:-}" ]]; then
        error "Falta la variable '$variable' ($description) en $ENV_FILE"
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

load_ssh_agent() {
    local ssh_agent_file="$HOME/.ssh/agent-env"

    print_info "Configurando ssh-agent..."

    # Si ya existe un agente guardado, cargarlo
    if [[ -f "$ssh_agent_file" ]]; then
        # shellcheck disable=SC1090
        source "$ssh_agent_file" > /dev/null 2>&1 || true
    fi

    # Si el socket no existe o no está configurado, arrancar uno nuevo
    if [[ -z "${SSH_AUTH_SOCK:-}" ]] || [[ ! -S "${SSH_AUTH_SOCK}" ]]; then
        print_info "Iniciando ssh-agent..."
        eval "$(ssh-agent -s)" > /dev/null

        mkdir -p "$HOME/.ssh"
        cat > "$ssh_agent_file" <<EOF
export SSH_AGENT_PID=$SSH_AGENT_PID
export SSH_AUTH_SOCK=$SSH_AUTH_SOCK
EOF
        chmod 600 "$ssh_agent_file"
    fi

    export SSH_AGENT_PID
    export SSH_AUTH_SOCK

    # Si la clave tiene passphrase o no está en el agente, cargarla
    if [[ -f "${SSH_PRIVATE_KEY}" ]]; then
        if ! ssh-add -l 2>/dev/null | grep -q "$(ssh-keygen -lf "${SSH_PRIVATE_KEY}" 2>/dev/null | awk '{print $2}')"; then
            print_info "Cargando clave SSH en ssh-agent..."
            print_info "Si la clave tiene passphrase, introdúcela cuando se solicite; se verá al escribirla."

            if ssh-add "${SSH_PRIVATE_KEY}"; then
                print_success "Clave SSH cargada en ssh-agent"
            else
                print_warning "No se pudo cargar la clave SSH"
            fi
        else
            print_info "Clave SSH ya está cargada en ssh-agent"
        fi
    fi
}

run_playbook() {
    local name="$1"
    local playbook="$2"

    print_header "Instalando: $name"

    if [[ ! -f "$PLAYBOOKS_DIR/$playbook" ]]; then
        error "No existe el playbook: $PLAYBOOKS_DIR/$playbook"
    fi

    ansible-playbook \
        -i "$INVENTORY" \
        --private-key "$SSH_PRIVATE_KEY" \
        "$PLAYBOOKS_DIR/$playbook"

    print_success "$name instalado/configurado correctamente."
    echo
}

show_menu() {
    echo "========================================="
    echo " Provisionamiento de servicios"
    echo "========================================="
    echo
    echo "  1) Traefik"
    echo "  2) Docker"
    echo "  3) Firewall"
    echo "  0) Salir"
    echo
}

# ============================================================
# INICIO
# ============================================================

print_header "Provisionamiento de Servicios"

load_env

# ============================================================
# Verificar variables requeridas
# ============================================================

print_info "Verificando configuración..."
echo

require_variable "VPS_IP" "IP del servidor"
require_variable "VPS_USER" "Usuario del VPS"
require_variable "SSH_PRIVATE_KEY" "Ruta de clave SSH privada"

# ============================================================
# Verificar estructura
# ============================================================

check_structure
check_ssh_key

# Cargar ssh-agent si es necesario
if [[ "${SSH_KEY_PASSPHRASE:-false}" == "true" ]]; then
    load_ssh_agent
fi

# ============================================================
# Mostrar configuración
# ============================================================

echo "Conectando a:"
echo "  Usuario: $VPS_USER"
echo "  IP:      $VPS_IP"
echo "  Clave:   $SSH_PRIVATE_KEY"
echo

# ============================================================
# Menú interactivo
# ============================================================

while true; do
    echo
    show_menu
    
    read -rp "Selecciona una opción: " OPTION
    
    case "$OPTION" in
        1)
            run_playbook "Traefik" "traefik.yml"
            ;;
        2)
            run_playbook "Docker" "docker.yml"
            docker_post_install_flow
            ;;
        3)
            run_playbook "Firewall" "firewall.yml"
            ;;
        0)
            print_info "Saliendo..."
            echo
            exit 0
            ;;
        *)
            print_warning "Opción no válida. Selecciona una opción del menú."
            ;;
    esac

done
