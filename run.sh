#!/usr/bin/env bash

set -euo pipefail

ENV_FILE="./.env"
SCRIPTS_DIR="./scripts/bash/run"

# ============================================================
# CONFIGURACIÓN DE COLORES
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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
    exit 1
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

load_env() {
    if [[ -f "$ENV_FILE" ]]; then
        set -a
        # shellcheck disable=SC1090
        source "$ENV_FILE"
        set +a
    fi
}

require_variable() {
    local variable="$1"
    local description="$2"

    if [[ -z "${!variable:-}" ]]; then
        print_error "Falta la variable '$variable' ($description)"
    fi
}

run_script() {
    local script="$1"
    local description="${2:-$script}"

    print_header "$description"

    if [[ ! -f "$SCRIPTS_DIR/$script" ]]; then
        print_error "No existe: $SCRIPTS_DIR/$script"
    fi

    if [[ ! -x "$SCRIPTS_DIR/$script" ]]; then
        print_info "Añadiendo permisos de ejecución..."
        chmod +x "$SCRIPTS_DIR/$script"
    fi

    if "$SCRIPTS_DIR/$script"; then
        print_success "Completado: $description"
        echo
    else
        print_error "Falló: $description"
    fi
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

    # Si la clave existe y tiene passphrase o no está en el agente, cargarla
    if [[ -n "${SSH_PRIVATE_KEY:-}" ]] && [[ -f "${SSH_PRIVATE_KEY}" ]]; then
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

# ============================================================
# MENU PRINCIPAL
# ============================================================

show_main_menu() {
    print_header "Configurador Automático de VPS"

    echo "¿Qué deseas hacer?"
    echo
    echo "  1) Configuración inicial completa (RECOMENDADO PRIMERA VEZ)"
    echo "  2) Continuar con configuración existente"
    echo "  3) Ver/Editar configuración (.env)"
    echo "  0) Salir"
    echo
}

# ============================================================
# INICIO PRINCIPAL
# ============================================================

print_header "Configurador Automático de VPS"

# Hacer ejecutables los scripts
chmod +x "$SCRIPTS_DIR"/*.sh 2>/dev/null || true

while true; do
    show_main_menu
    
    read -rp "Selecciona una opción: " OPTION
    
    case "$OPTION" in
        1)
            # ========================================================
            # CONFIGURACIÓN INICIAL COMPLETA
            # ========================================================
            
            print_header "Configuración Inicial Completa"
            
            echo "Se ejecutarán los siguientes pasos:"
            echo
            echo "  1. Verificar dependencias"
            echo "  2. Configuración interactiva (.env)"
            echo "  3. Primer acceso al servidor (como root)"
            echo "  4. Creación de usuario no-root"
            echo "  5. Configuración de SSH segura"
            echo "  6. Configuración de Ansible"
            echo
            
            read -rp "¿Deseas continuar? [s/n]: " confirm
            
            if [[ "$confirm" =~ ^[sS]$ ]]; then
                # Verificar dependencias
                run_script "01-check-deps.sh" "Verificar dependencias"
                
                # Configuración interactiva
                run_script "02-interactive-setup.sh" "Configuración interactiva (.env)"
                
                # Cargar configuración
                load_env
                
                # Validar configuración
                require_variable "VPS_IP" "IP del servidor"
                require_variable "VPS_USER" "Usuario del VPS"
                require_variable "VPS_PASSWORD" "Contraseña de root"
                require_variable "SSH_PRIVATE_KEY" "Ruta de clave SSH privada"
                require_variable "SSH_PUBLIC_KEY" "Ruta de clave SSH pública"

                if [[ -n "${SSH_PRIVATE_KEY:-}" && -f "${SSH_PRIVATE_KEY}" && -n "${SSH_PUBLIC_KEY:-}" && -f "${SSH_PUBLIC_KEY}" ]]; then
                    if [[ "$(ssh-keygen -y -f "${SSH_PRIVATE_KEY}" 2>/dev/null || true)" != "$(cat "${SSH_PUBLIC_KEY}" 2>/dev/null || true)" ]]; then
                        print_error "La clave SSH pública no coincide con la privada. Reconfigura la clave SSH."
                    fi
                fi

                # Primer acceso
                run_script "03-first-vps-login.sh" "Primer acceso al servidor (root)"
                
                # Configurar el usuario que se quiere crear en el VPS
                run_script "04-user-config.sh" "Crear usuario no-root"
                
                # Generar primero el inventario y las variables de Ansible para el usuario nuevo.
                # El playbook de usuario depende de ellas para resolver username y ssh_public_key.
                run_script "05-generate-ansible-vars.sh" "Generar variables de Ansible"
                
                # Crear el usuario real en el servidor usando acceso root y luego validar acceso con la clave
                run_script "06-bootstrap-user.sh" "Bootstrap del usuario"
                
                # Configurar SSH seguro una vez que el usuario ya existe y puede autenticarse por clave
                run_script "07-secure-ssh.sh" "Securizar SSH"
                
                print_header "¡Configuración Completada!"
                
                echo "Tu servidor está listo para provisionar aplicaciones."
                echo
                echo "Próximo paso: ejecuta './provision.sh' para instalar servicios"
                echo
            fi
            ;;
            
        2)
            # ========================================================
            # CONTINUAR CON CONFIGURACIÓN EXISTENTE
            # ========================================================
            
            load_env
            
            if [[ -z "${VPS_IP:-}" ]]; then
                print_error "No hay configuración previa en .env. Ejecuta primero la opción 1."
            fi
            
            print_header "Continuar con Configuración Existente"
            
            echo "Configuración actual:"
            echo
            echo "  VPS_IP:        ${VPS_IP}"
            echo "  VPS_USER:      ${VPS_USER}"
            echo "  SSH_KEY:       ${SSH_KEY_NAME:-[no configurada]}"
            echo
            
            read -rp "¿Deseas continuar con esta configuración? [s/n]: " confirm
            
            if [[ "$confirm" =~ ^[sS]$ ]]; then
                # Cargar ssh-agent si la clave tiene passphrase
                load_ssh_agent
                
                # Solo ejecutar scripts de bootstrap
                run_script "06-bootstrap-user.sh" "Bootstrap del usuario"
                
                print_success "El servidor está listo para provisionar aplicaciones"
                echo
                echo "Próximo paso: ejecuta './provision.sh' para instalar servicios"
                echo
            fi
            ;;
            
        3)
            # ========================================================
            # VER/EDITAR CONFIGURACIÓN
            # ========================================================
            
            if [[ ! -f "$ENV_FILE" ]]; then
                print_error "No existe $ENV_FILE. Ejecuta primero la opción 1 o 2."
            fi
            
            print_header "Configuración Actual (.env)"
            
            # Mostrar .env sin mostrar contraseñas
            grep -v "VPS_PASSWORD" "$ENV_FILE" || print_warning "El archivo .env está vacío"
            echo
            print_warning "Las contraseñas no se muestran por seguridad"
            echo
            
            # Ofrecer editar
            read -rp "¿Deseas ejecutar la configuración interactiva? [s/n]: " confirm
            
            if [[ "$confirm" =~ ^[sS]$ ]]; then
                run_script "02-interactive-setup.sh" "Editar configuración"
            fi
            ;;
            
        0)
            print_info "Saliendo..."
            exit 0
            ;;
            
        *)
            print_error "Opción no válida. Introduce 0, 1, 2 o 3."
            ;;
    esac
    
    echo
done
# ============================================================
# CONFIGURACIÓN POSTERIOR
# ============================================================

run_script "90-setup-base.sh"

# ------------------------------------------------------------
# Final
# ------------------------------------------------------------

echo
echo "========================================="
echo -e "${GREEN} Proceso completado correctamente${NC}"
echo "========================================="
echo
