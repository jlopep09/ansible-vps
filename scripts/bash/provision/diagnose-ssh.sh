#!/usr/bin/env bash

set -euo pipefail

# ============================================================
# DIAGNÓSTICO DE PROBLEMA CON SSH
# ============================================================

echo "========================================="
echo " Diagnóstico SSH Agent"
echo "========================================="
echo

# 1. Verificar si ssh-agent está corriendo
echo "[1] Comprobando ssh-agent..."

if pgrep -u "$USER" ssh-agent > /dev/null 2>&1; then
    echo "    ✓ ssh-agent está ejecutándose"
    AGENT_PID=$(pgrep -u "$USER" ssh-agent | head -1)
    echo "    PID: $AGENT_PID"
else
    echo "    ✗ ssh-agent NO está ejecutándose"
    echo "    → El sistema debe iniciar ssh-agent automáticamente"
fi

echo

# 2. Verificar variables de entorno
echo "[2] Verificando variables de entorno..."

if [[ -n "${SSH_AUTH_SOCK:-}" ]]; then
    echo "    ✓ SSH_AUTH_SOCK está configurado"
    echo "    Valor: $SSH_AUTH_SOCK"
else
    echo "    ✗ SSH_AUTH_SOCK no está configurado"
fi

if [[ -n "${SSH_AGENT_PID:-}" ]]; then
    echo "    ✓ SSH_AGENT_PID está configurado"
    echo "    Valor: $SSH_AGENT_PID"
else
    echo "    ✗ SSH_AGENT_PID no está configurado"
fi

echo

# 3. Verificar claves cargadas
echo "[3] Claves en el agente..."

if [[ -n "${SSH_AUTH_SOCK:-}" ]]; then
    if ssh-add -l 2>/dev/null; then
        echo "    ✓ Claves encontradas en el agente"
    else
        echo "    ✗ No hay claves en el agente"
    fi
else
    echo "    ✗ No se puede conectar al agente (SSH_AUTH_SOCK no configurado)"
fi

echo

# 4. Verificar archivos .env
echo "[4] Verificando configuración .env..."

if [[ -f ".env" ]]; then
    echo "    ✓ Archivo .env existe"
    
    if grep -q "SSH_PRIVATE_KEY" .env; then
        SSH_KEY_PATH=$(grep "^SSH_PRIVATE_KEY=" .env | cut -d= -f2)
        echo "    SSH_PRIVATE_KEY: $SSH_KEY_PATH"
        
        if [[ -f "$SSH_KEY_PATH" ]]; then
            echo "    ✓ Archivo de clave privada existe"
            
            # Verificar permisos
            PERMS=$(stat -c%a "$SSH_KEY_PATH" 2>/dev/null || stat -f%A "$SSH_KEY_PATH" 2>/dev/null)
            echo "    Permisos: $PERMS"
            
            if [[ "$PERMS" == "600" ]] || [[ "$PERMS" == "rw-------" ]]; then
                echo "    ✓ Permisos correctos (600)"
            else
                echo "    ✗ Permisos incorrectos (debería ser 600)"
            fi
        else
            echo "    ✗ Archivo de clave privada no existe: $SSH_KEY_PATH"
        fi
    fi
else
    echo "    ✗ Archivo .env no existe"
fi

echo

# 5. Prueba de conexión SSH
echo "[5] Prueba de conexión SSH..."

if [[ -f ".env" ]]; then
    VPS_IP=$(grep "^VPS_IP=" .env | cut -d= -f2 || echo "")
    VPS_USER=$(grep "^VPS_USER=" .env | cut -d= -f2 || echo "")
    SSH_KEY=$(grep "^SSH_PRIVATE_KEY=" .env | cut -d= -f2 || echo "")
    
    if [[ -n "$VPS_IP" ]] && [[ -n "$VPS_USER" ]] && [[ -n "$SSH_KEY" ]]; then
        echo "    Configuración encontrada:"
        echo "    - Host: $VPS_USER@$VPS_IP"
        echo "    - Clave: $SSH_KEY"
        echo
        
        echo "    Intentando conexión SSH..."
        if ssh -i "$SSH_KEY" -o ConnectTimeout=5 "$VPS_USER@$VPS_IP" "echo OK" 2>&1; then
            echo "    ✓ Conexión SSH exitosa"
        else
            echo "    ✗ Conexión SSH fallida"
            echo "    → Esto puede ser normal si la clave tiene passphrase y no está cargada"
        fi
    else
        echo "    ✗ Configuración incompleta en .env"
    fi
fi

echo

# 6. Resumen y recomendaciones
echo "========================================="
echo " RECOMENDACIONES"
echo "========================================="
echo

echo "Si la clave tiene passphrase:"
echo "1. Carga la clave manualmente:"
echo "   $ ssh-add private/tu_clave"
echo
echo "2. O ejecuta los scripts nuevamente que pedirán la passphrase"
echo
echo "Si ssh-agent no está corriendo:"
echo "1. Inicialo:"
echo "   $ eval \$(ssh-agent -s)"
echo
echo "Si los permisos están mal:"
echo "1. Corrige los permisos:"
echo "   $ chmod 600 private/*"
echo
echo "Para más información, consulta:"
echo "   $ cat SETUP_GUIDE.md"
echo "   $ cat CAMBIOS_REALIZADOS.md"
echo
