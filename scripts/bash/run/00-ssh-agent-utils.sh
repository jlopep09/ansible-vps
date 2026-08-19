#!/usr/bin/env bash

set -euo pipefail

# ============================================================
# FUNCIONES DE SOPORTE PARA SSH-AGENT
# ============================================================

# Inicializar ssh-agent si no está corriendo
init_ssh_agent() {
    local ssh_agent_file="$HOME/.ssh/agent-env"

    # Si ya existe un agente guardado, cargar sus variables
    if [[ -f "$ssh_agent_file" ]]; then
        source "$ssh_agent_file" > /dev/null 2>&1 || true
    fi

    # Si el agente ya está activo y tiene socket válido, guardar la sesión actual
    if [[ -n "${SSH_AUTH_SOCK:-}" ]] && [[ -S "${SSH_AUTH_SOCK}" ]] && ssh-add -l >/dev/null 2>&1; then
        export SSH_AGENT_PID
        export SSH_AUTH_SOCK
        return 0
    fi

    # Si no hay socket válido, reiniciar o arrancar uno nuevo
    if [[ -n "${SSH_AGENT_PID:-}" ]] && kill -0 "${SSH_AGENT_PID}" 2>/dev/null; then
        export SSH_AGENT_PID
        export SSH_AUTH_SOCK
        return 0
    fi

    # Iniciar nuevo agente
    eval "$(ssh-agent -s)" > /dev/null

    # Guardar variables para futuras sesiones
    mkdir -p "$HOME/.ssh"
    cat > "$ssh_agent_file" <<EOF
export SSH_AGENT_PID=$SSH_AGENT_PID
export SSH_AUTH_SOCK=$SSH_AUTH_SOCK
EOF
    chmod 600 "$ssh_agent_file"

    export SSH_AGENT_PID
    export SSH_AUTH_SOCK
}

# Cargar clave en ssh-agent
load_ssh_key_interactive() {
    local key_path="$1"
    
    # Primero inicializar el agente
    init_ssh_agent
    
    # Comprobar si la clave ya está en el agente
    if ssh-add -l 2>/dev/null | grep -q "$(ssh-keygen -lf "$key_path" 2>/dev/null | awk '{print $2}')"; then
        return 0  # Ya está cargada
    fi
    
    # Cargar la clave de forma interactiva
    echo "[INFO] Cargando clave SSH en ssh-agent..."
    echo "[INFO] Si la clave tiene passphrase, introdúcela cuando se solicite; se mostrará al escribirla."
    echo
    
    if ssh-add "$key_path"; then
        echo
        return 0
    else
        return 1
    fi
}

# Garantiza que la clave privada esté cargada en ssh-agent.
# Si la clave tiene passphrase, la pedirá y la cargará automáticamente.
ensure_private_key_loaded() {
    local key_path="${1:-}"

    if [[ -z "$key_path" ]] || [[ ! -f "$key_path" ]]; then
        return 1
    fi

    init_ssh_agent

    local key_fingerprint
    key_fingerprint="$(ssh-keygen -lf "$key_path" 2>/dev/null | awk '{print $2}')"
    if [[ -z "$key_fingerprint" ]]; then
        return 1
    fi

    if ssh-add -l 2>/dev/null | grep -q "$key_fingerprint"; then
        export SSH_AUTH_SOCK
        export SSH_AGENT_PID
        return 0
    fi

    echo "[INFO] La clave SSH necesita ser cargada en ssh-agent."
    echo "[INFO] Si la clave tiene passphrase, te la pedirá ahora."
    if ssh-add "$key_path"; then
        export SSH_AUTH_SOCK
        export SSH_AGENT_PID
        return 0
    fi

    return 1
}

# Conectar SSH con soporte para ssh-agent
ssh_connect_with_agent() {
    local key_path="$1"
    local host="$2"
    local command="$3"
    
    # Inicializar agente si es necesario
    init_ssh_agent
    
    # Intentar cargar clave
    if ! ssh-add -l 2>/dev/null | grep -q "$(ssh-keygen -lf "$key_path" 2>/dev/null | awk '{print $2}')"; then
        load_ssh_key_interactive "$key_path" || return 1
    fi
    
    # Ejecutar SSH con el agente
    SSH_AUTH_SOCK="$SSH_AUTH_SOCK" ssh \
        -i "$key_path" \
        -o StrictHostKeyChecking=accept-new \
        -o UserKnownHostsFile="$HOME/.ssh/known_hosts" \
        -o ConnectTimeout=15 \
        "$host" \
        "$command"
}

# Exportar funciones
export -f init_ssh_agent
export -f load_ssh_key_interactive
export -f ssh_connect_with_agent
