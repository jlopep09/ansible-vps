#!/usr/bin/env bash

set -euo pipefail

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
                echo "Respuesta no válida. Introduce 's' o 'n'."
                ;;
        esac
    done
}

install_python() {
    echo "[INFO] Actualizando índices de paquetes..."
    sudo apt-get update

    echo "[INFO] Instalando Python..."
    sudo apt-get install -y python3 python3-pip

    echo "[OK] Python instalado correctamente."
}

install_ansible() {
    echo "[INFO] Actualizando índices de paquetes..."
    sudo apt-get update

    echo "[INFO] Instalando Ansible..."
    sudo apt-get install -y ansible

    echo "[OK] Ansible instalado correctamente."
}

echo "========================================="
echo " Comprobación de dependencias"
echo "========================================="
echo

# Comprobar Python
if command -v python3 >/dev/null 2>&1; then
    PYTHON_VERSION=$(python3 --version 2>&1)
    echo "[OK] Python encontrado: ${PYTHON_VERSION}"
else
    echo "[WARN] Python no está instalado."

    if ask_yes_no "¿Deseas instalar Python?"; then
        install_python
    else
        echo "[ERROR] Python es necesario para continuar."
        exit 1
    fi
fi

echo

# Comprobar Ansible
if command -v ansible >/dev/null 2>&1; then
    ANSIBLE_VERSION=$(ansible --version | head -n 1)
    echo "[OK] Ansible encontrado: ${ANSIBLE_VERSION}"
else
    echo "[WARN] Ansible no está instalado."

    if ask_yes_no "¿Deseas instalar Ansible?"; then
        install_ansible
    else
        echo "[INFO] Instalación de Ansible cancelada por el usuario."
        exit 0
    fi
fi

echo
echo "[OK] Todas las comprobaciones han finalizado correctamente."
