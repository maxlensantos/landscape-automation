#!/bin/bash

# ANSI Color Codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Configuration ---
INVENTORY_FILE="inventory/production.ini"
PLAYBOOKS_DIR="playbooks"
SCRIPTS_DIR="scripts"

# --- Helper Functions ---
press_enter_to_continue() {
    echo -e "\n${YELLOW}Pressione Enter para continuar...${NC}"
    read
}

# --- Menu Functions ---

run_preflight_checks() {
    echo -e "${BLUE}--- Executando Script de Validação (Pré-voo) ---${NC}"
    if [ -f "${SCRIPTS_DIR}/validate-deployment.py" ]; then
        chmod +x "${SCRIPTS_DIR}/validate-deployment.py"
        python3 "${SCRIPTS_DIR}/validate-deployment.py"
    else
        echo -e "${RED}ERRO: Script ${SCRIPTS_DIR}/validate-deployment.py não encontrado.${NC}"
    fi
    press_enter_to_continue
}

run_diagnostics() {
    echo -e "${BLUE}--- Executando Diagnóstico do Ambiente (Playbook 00) ---${NC}"
    if [ -f "${PLAYBOOKS_DIR}/00-diagnostic.yml" ]; then
        ansible-playbook -i "${INVENTORY_FILE}" "${PLAYBOOKS_DIR}/00-diagnostic.yml"
    else
        echo -e "${RED}ERRO: Playbook ${PLAYBOOKS_DIR}/00-diagnostic.yml não encontrado.${NC}"
    fi
    press_enter_to_continue
}

prepare_nodes() {
    echo -e "${BLUE}--- Preparando Nós dos Hosts (Playbook 00) ---${NC}"
    if [ -f "${PLAYBOOKS_DIR}/00-prepare-host-nodes.yml" ]; then
        ansible-playbook -i "${INVENTORY_FILE}" "${PLAYBOOKS_DIR}/00-prepare-host-nodes.yml"
    else
        echo -e "${RED}ERRO: Playbook ${PLAYBOOKS_DIR}/00-prepare-host-nodes.yml não encontrado.${NC}"
    fi
    press_enter_to_continue
}

run_full_deployment() {
    echo -e "${BLUE}--- Iniciando Deploy Completo do Landscape HA (Macro Playbook) ---${NC}"
    echo -e "${YELLOW}AVISO: Este processo é longo e pode levar mais de 30 minutos.${NC}"
    read -p "Deseja continuar? (s/n): " choice
    if [[ "$choice" == "s" || "$choice" == "S" ]]; then
        if [ -f "${PLAYBOOKS_DIR}/macro-deploy-manual-ha.yml" ]; then
            ansible-playbook -i "${INVENTORY_FILE}" "${PLAYBOOKS_DIR}/macro-deploy-manual-ha.yml"
        else
            echo -e "${RED}ERRO: Playbook ${PLAYBOOKS_DIR}/macro-deploy-manual-ha.yml não encontrado.${NC}"
        fi
    else
        echo "Deploy cancelado."
    fi
    press_enter_to_continue
}

destroy_environment() {
    echo -e "${RED}--- DESTRUINDO AMBIENTE LANDSCAPE ---${NC}"
    echo -e "${YELLOW}AVISO: Esta ação é IRREVERSÍVEL e irá remover o controller e modelo Juju.${NC}"
    read -p "Você tem CERTEZA ABSOLUTA que deseja continuar? (digite 'sim' para confirmar): " choice
    if [[ "$choice" == "sim" ]]; then
        echo "Funcionalidade de destruição ainda não implementada."
        # Placeholder for destroy playbook
        # ansible-playbook -i "${INVENTORY_FILE}" "${PLAYBOOKS_DIR}/99-destroy-environment.yml"
    else
        echo "Destruição cancelada."
    fi
    press_enter_to_continue
}


# --- Main Menu Loop ---

verify_juju_version() {
    echo -e "${BLUE}--- Verificando a versão do Juju ---${NC}"
    # Check if juju is installed
    if ! command -v juju &> /dev/null; then
        echo -e "${RED}ERRO: O comando 'juju' não foi encontrado.${NC}"
        echo -e "${YELLOW}Por favor, instale o Juju com o comando:${NC}"
        echo "sudo snap install juju --classic --channel=3.5/stable"
        exit 1
    fi

    JUJU_VERSION=$(juju version)
    
    # Check if the version string contains "3.5."
    if [[ "$JUJU_VERSION" == *"3.5."* ]]; then
        echo -e "${GREEN}Versão do Juju ($JUJU_VERSION) é compatível.${NC}"
    else
        echo -e "${RED}ERRO: Versão incompatível do Juju detectada: $JUJU_VERSION${NC}"
        echo -e "${YELLOW}Esta automação requer Juju da série 3.5.x para funcionar corretamente.${NC}"
        echo -e "${YELLOW}Por favor, corrija a versão com os seguintes comandos:${NC}"
        echo "1. sudo snap remove --purge juju"
        echo "2. sudo snap install juju --classic --channel=3.5/stable"
        exit 1
    fi
    echo "" # Add a newline for better formatting
}

# --- Main Execution ---
verify_juju_version

while true; do
    clear
    echo -e "${BLUE}===================================================${NC}"
    echo -e "${BLUE}  Gerenciador de Deploy - Canonical Landscape HA   ${NC}"
    echo -e "${BLUE}===================================================${NC}"
    echo "1. Executar Validação de Pré-voo (Script Python)"
    echo "2. Executar Diagnóstico do Ambiente (Playbook Ansible)"
    echo "3. Preparar Nós dos Hosts (Instalar LXD, Juju, etc.)"
    echo -e "${GREEN}4. EXECUTAR DEPLOY COMPLETO${NC}"
    echo -e "${RED}5. DESTRUIR AMBIENTE${NC}"
    echo "6. Sair"
    echo -e "${BLUE}---------------------------------------------------${NC}"
    read -p "Escolha uma opção [1-6]: " choice

    case $choice in
        1) run_preflight_checks ;;
        2) run_diagnostics ;;
        3) prepare_nodes ;;
        4) run_full_deployment ;;
        5) destroy_environment ;;
        6) echo "Saindo..."; exit 0 ;;
        *) echo -e "${RED}Opção inválida. Tente novamente.${NC}"; press_enter_to_continue ;;
    esac
done