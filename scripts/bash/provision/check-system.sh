#!/usr/bin/env bash

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
PASSED=0
FAILED=0
WARNINGS=0

check_passed() {
    echo -e "${GREEN}✓${NC} $1"
    ((PASSED++))
}

check_failed() {
    echo -e "${RED}✗${NC} $1"
    ((FAILED++))
}

check_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((WARNINGS++))
}

check_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_header() {
    echo
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo -e "${BLUE} $1${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo
}

# ============================================================
# VERIFICACIONES
# ============================================================

print_header "Verificación de Configuración del Proyecto"

# ============================================================
# 1. Verificar estructura de directorios
# ============================================================

print_header "1. Estructura de Directorios"

[[ -d "scripts" ]] && check_passed "Directorio scripts/" || check_failed "Falta scripts/"
[[ -d "scripts/bash/run" ]] && check_passed "Directorio scripts/bash/run/" || check_failed "Falta scripts/bash/run/"
[[ -d "scripts/bash/provision" ]] && check_passed "Directorio scripts/bash/provision/" || check_failed "Falta scripts/bash/provision/"
[[ -d "ansible" ]] && check_passed "Directorio ansible/" || check_failed "Falta ansible/"
[[ -d "private" ]] && check_passed "Directorio private/" || check_warning "Directorio private/ (se creará automáticamente)"
[[ -f "run.sh" ]] && check_passed "Archivo run.sh" || check_failed "Falta run.sh"
[[ -f "provision.sh" ]] && check_passed "Archivo provision.sh" || check_failed "Falta provision.sh"

# ============================================================
# 2. Verificar scripts principales
# ============================================================

print_header "2. Scripts Principales"

scripts_check=(
    "scripts/bash/run/01-check-deps.sh"
    "scripts/bash/run/03-first-vps-login.sh"
    "scripts/bash/provision/ssh-key.sh"
    "scripts/bash/run/04-user-config.sh"
    "scripts/bash/run/07-secure-ssh.sh"
    "scripts/bash/run/05-generate-ansible-vars.sh"
    "scripts/bash/run/06-bootstrap-user.sh"
    "scripts/bash/run/02-interactive-setup.sh"
)

for script in "${scripts_check[@]}"; do
    if [[ -f "$script" ]]; then
        if [[ -x "$script" ]]; then
            check_passed "$script (ejecutable)"
        else
            check_warning "$script (no ejecutable - se arreglará automáticamente)"
        fi
    else
        check_failed "Falta $script"
    fi
done

# ============================================================
# 3. Verificar archivos de configuración
# ============================================================

print_header "3. Archivos de Configuración"

[[ -f "ansible/ansible.cfg" ]] && check_passed "ansible/ansible.cfg" || check_failed "Falta ansible.cfg"
[[ -f ".env.example" ]] && check_passed ".env.example (plantilla)" || check_failed "Falta .env.example"
[[ -f ".gitignore" ]] && check_passed ".gitignore" || check_warning "Falta .gitignore (se creará)"
[[ -f ".env" ]] && check_info ".env existe (configuración actual)" || check_info "Sin .env (se creará en setup)"

# ============================================================
# 4. Verificar playbooks
# ============================================================

print_header "4. Playbooks Ansible"

playbooks_check=(
    "ansible/playbooks/user.yml"
    "ansible/playbooks/docker.yml"
    "ansible/playbooks/ghcr-login.yml"
    "ansible/playbooks/traefik.yml"
    "ansible/playbooks/firewall.yml"
    "ansible/playbooks/ssh.yml"
    "ansible/playbooks/dependencies.yml"
)

for playbook in "${playbooks_check[@]}"; do
    [[ -f "$playbook" ]] && check_passed "$playbook" || check_warning "No encontrado: $playbook"
done

# ============================================================
# 5. Verificar dependencias del sistema
# ============================================================

print_header "5. Dependencias del Sistema"

commands_check=(
    "bash:bash"
    "ssh:openssh-client"
    "ansible:ansible"
    "python3:python3"
)

for cmd_info in "${commands_check[@]}"; do
    cmd="${cmd_info%:*}"
    pkg="${cmd_info#*:}"
    
    if command -v "$cmd" &> /dev/null; then
        version=$("$cmd" --version 2>&1 | head -1 || echo "desconocida")
        check_passed "$cmd instalado"
    else
        check_failed "$cmd NO instalado (instala: $pkg)"
    fi
done

# sshpass es más flexible
if command -v sshpass &> /dev/null; then
    check_passed "sshpass instalado"
else
    check_warning "sshpass NO instalado (necesario para primer acceso)"
fi

# ============================================================
# 6. Verificar permisos
# ============================================================

print_header "6. Permisos"

if [[ -f ".env" ]]; then
    perms=$(stat -f%A ".env" 2>/dev/null || stat -c%a ".env" 2>/dev/null)
    if [[ "$perms" == "600" ]] || [[ "$perms" == "rw-------" ]]; then
        check_passed ".env tiene permisos seguros (600)"
    else
        check_warning ".env tiene permisos: $perms (debería ser 600)"
    fi
fi

# ============================================================
# 7. Verificar .gitignore
# ============================================================

print_header "7. Seguridad - .gitignore"

if [[ -f ".gitignore" ]]; then
    if grep -q "^\.env$\|^\\.env$" .gitignore; then
        check_passed ".env está en .gitignore"
    else
        check_failed ".env NO está en .gitignore ⚠️"
    fi
    
    if grep -q "^private/\|private/\*" .gitignore; then
        check_passed "private/ está en .gitignore"
    else
        check_failed "private/ NO está en .gitignore ⚠️"
    fi
else
    check_warning ".gitignore no existe"
fi

# ============================================================
# 8. Información de configuración actual
# ============================================================

if [[ -f ".env" ]]; then
    print_header "8. Configuración Actual (.env)"
    
    if [[ -r ".env" ]]; then
        # Mostrar sin mostrar credenciales
        check_info "Variables encontradas:"
        grep -v "PASSWORD\|PASSPHRASE" .env | sed 's/^/  /'
        check_warning "Las contraseñas no se muestran por seguridad"
    else
        check_failed ".env existe pero no es legible"
    fi
else
    print_header "8. Configuración (.env)"
    check_info "Sin configuración - Ejecuta './run.sh' para crear .env"
fi

# ============================================================
# RESUMEN
# ============================================================

print_header "RESUMEN"

echo -e "${GREEN}Pasadas:${NC}   $PASSED"
echo -e "${YELLOW}Advertencias:${NC} $WARNINGS"
echo -e "${RED}Fallos:${NC}    $FAILED"
echo

if [[ $FAILED -eq 0 ]]; then
    echo -e "${GREEN}✓ Verificación completada exitosamente${NC}"
    echo
    echo "Próximo paso: ejecuta './run.sh'"
    exit 0
else
    echo -e "${RED}✗ Hay problemas que deben resolverse${NC}"
    echo
    echo "Lee SETUP_GUIDE.md para más detalles"
    exit 1
fi
