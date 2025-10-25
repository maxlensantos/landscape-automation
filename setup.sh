#!/bin/bash

# setup.sh: Ponto de entrada para automação da implantação do Landscape.
# VERSÃO 5.0 - Versão final com fluxo de trabalho e UX aprimorados.

# Aborta o script se um comando falhar, se uma variável não estiver definida ou em erros de pipe.
set -euo pipefail

# Garante um tipo de terminal são, especialmente dentro do tmux
export TERM=screen
export PATH=$PATH:/snap/bin

# --- Paleta de Cores e Estilos ---
if command -v tput >/dev/null && [[ -n "$(tput setaf 1)" ]]; then
    GREEN=$(tput setaf 2); YELLOW=$(tput setaf 3); RED=$(tput setaf 1); BLUE=$(tput setaf 4)
    BOLD=$(tput bold); RESET=$(tput sgr0)
    TAG_INFO="${BLUE}[INFO]${RESET}"; TAG_WARN="${YELLOW}[WARN]${RESET}"; TAG_ACTION="${BLUE}[ACTION]${RESET}"
    TITLE_COLOR="${BOLD}${BLUE}"; HEADER_COLOR="${GREEN}"; PROMPT_COLOR="${BLUE}"; OPTION_COLOR="${BOLD}"; DESC_COLOR="${RESET}"; WARN_COLOR="${YELLOW}"; DANGER_COLOR="${RED}"
else # Fallback
    GREEN="\033[1;32m"; YELLOW="\033[1;33m"; RED="\033[1;31m"; BLUE="\033[1;34m"
    BOLD="\033[1m"; RESET="\033[0m"
    TAG_INFO="[INFO]"; TAG_WARN="[WARN]"; TAG_ACTION="[ACTION]"
    TITLE_COLOR="${BOLD}${BLUE}"; HEADER_COLOR="${GREEN}"; PROMPT_COLOR="${BLUE}"; OPTION_COLOR="${BOLD}"; DESC_COLOR="${RESET}"; WARN_COLOR="${YELLOW}"; DANGER_COLOR="${RED}"
fi

# --- Variáveis Globais ---
SCRIPT_VERSION="5.0"
VAULT_PASS_FILE="../vault_pass.txt"
ENV_NAME=""
INVENTORY_FILE=""
LAST_ACTION_STATUS=""
JUJU_MODEL_NAME=""
JUJU_CONTROLLER_NAME=""

# --- Funções Auxiliares ---
die() { echo -e "${DANGER_COLOR}ERRO: $1${RESET}" >&2; exit 1; }
confirm_action() { local prompt="$1"; local response; read -r -p "$(echo -e "${TAG_ACTION} ${WARN_COLOR}${prompt} [s/N]: ${RESET}")" response; response=${response:-N}; if [[ "$response" =~ ^[Ss]$ ]]; then return 0; else echo -e "${RED}Ação cancelada.${RESET}"; return 1; fi; }
pause_and_continue() { echo -e "${DESC_COLOR}"; read -r -p "Pressione [Enter] para continuar..." && echo -e "${RESET}" || echo -e "${RESET}"; }
is_playbook_implemented() { local playbook_file="playbooks/$1"; if [ -f "$playbook_file" ]; then return 0; else return 1; fi; }

# --- Funções de Execução ---
run_playbook() {
    local playbook_file="$1"
    local foreground_log="/tmp/ansible_foreground_run.log"
    
    if ! is_playbook_implemented "$playbook_file"; then
        echo -e "${WARN_COLOR}Aviso: O Playbook 'playbooks/${playbook_file}' não está implementado.${RESET}"
        return 1
    fi

    echo -e "\n${PROMPT_COLOR}Executando o playbook: ${playbook_file} no ambiente: ${ENV_NAME}${RESET}"
    echo -e "${TAG_INFO} A saída completa será registrada em '${foreground_log}'.${RESET}"
    
    local ansible_args=()
    if [ -f "$VAULT_PASS_FILE" ]; then
        ansible_args+=("--vault-password-file" "$VAULT_PASS_FILE")
    fi
    
    local playbook_exit_code=0
    ansible-playbook -i "${INVENTORY_FILE}" "playbooks/${playbook_file}" "${ansible_args[@]}" > "$foreground_log" 2>&1 || playbook_exit_code=$?

    echo -e "\n${HEADER_COLOR}--- Saída do Playbook '${playbook_file}' ---${RESET}"
    cat "$foreground_log"
    echo -e "${HEADER_COLOR}--- Fim da Saída do Playbook ---${RESET}\n"

    if [ $playbook_exit_code -eq 0 ]; then
        echo -e "${GREEN}✓ Playbook '${playbook_file}' concluído com sucesso.${RESET}"
        rm -f "$foreground_log"
        return 0
    else
        echo -e "${DANGER_COLOR}✗ ERRO: O playbook '${playbook_file}' falhou. O log foi preservado em '${foreground_log}'.${RESET}"
        return 1
    fi
}

# --- Funções de Lógica e Menu ---
load_env_vars_from_inventory() {
    local env_file="$1"
    JUJU_MODEL_NAME=$(awk -F'=' '/^model_name/{print $2}' "$env_file" 2>/dev/null | tr -d ' ' || echo "")
    JUJU_CONTROLLER_NAME=$(awk -F'=' '/^controller_name/{print $2}' "$env_file" 2>/dev/null | tr -d ' ' || echo "")
}

run_inventory_configurator_wizard() {
    local inventory_file="$1"
    local env_name_for_wizard="$2"
    local num_nodes
    local node_details=""
    local all_vars_section=""
    local jump_host_spec=""
    local ansible_user_input=""
    local ssh_key_path_input=""

    clear
    echo -e "${TITLE_COLOR}=== CONFIGURAÇÃO INTERATIVA DO INVENTÁRIO DE ${env_name_for_wizard^^} ===${RESET}"
    echo -e "${TAG_INFO} Este assistente irá guiá-lo na criação do seu '${inventory_file}'."

    while true; do
        read -r -p "$(echo -e "${TAG_ACTION} Quantos nós o cluster ${env_name_for_wizard} terá? [Padrão: 2]: ${RESET}")" num_nodes
        num_nodes=${num_nodes:-2}
        if [[ "$num_nodes" =~ ^[1-9][0-9]*$ ]]; then break; else echo -e "${DANGER_COLOR}Número inválido.${RESET}"; fi
    done

    read -r -p "$(echo -e "${TAG_ACTION} Qual usuário para conexão SSH (ansible_user)? [Padrão: serpro]: ${RESET}")" ansible_user_input
    ansible_user_input=${ansible_user_input:-serpro}

    read -r -p "$(echo -e "${TAG_ACTION} Caminho para a chave SSH privada? [Padrão: ~/.ssh/id_ed25519]: ${RESET}")" ssh_key_path_input
    ssh_key_path_input=${ssh_key_path_input:-~/.ssh/id_ed25519}

    if confirm_action "Deseja utilizar um Bastion Host (Servidor de Entreposto)?"; then
        read -r -p "$(echo -e "${TAG_ACTION} Informe o usuário e o endereço do Bastion Host (user@host): ${RESET}")" jump_host_spec
        if [ -n "$jump_host_spec" ]; then
            all_vars_section+="ansible_ssh_common_args='-o ProxyJump=$jump_host_spec -A'\n"
        fi
    fi

    for i in $(seq 1 "$num_nodes"); do
        local node_name="${env_name_for_wizard,,}-$(printf "%02d" "$i")"
        local default_ansible_host="10.35.0.$(($i + 8))"
        local ansible_host_input=""
        echo -e "\n${HEADER_COLOR}--- Configurando Nó ${i} (${node_name}) ---${RESET}"
        read -r -p "$(echo -e "${TAG_ACTION} IP de gerenciamento (ansible_host) para ${node_name} [Padrão: ${default_ansible_host}]: ${RESET}")" ansible_host_input
        ansible_host_input=${ansible_host_input:-$default_ansible_host}
        node_details+="${node_name} ansible_host=${ansible_host_input}\n"
    done

    local sanitized_env_name=$(echo "$env_name_for_wizard" | sed 'y/áàâãäéèêëíìîïóòôõöúùûüç/aaaaaeeeeiiiiooooouuuuc/' | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')
    local final_inventory_content="# Inventário para o ambiente de ${env_name_for_wizard}\n\n"
    final_inventory_content+="[lxd_hosts]\n${node_details}\n"
    final_inventory_content+="[all:vars]\n"
    final_inventory_content+="ansible_user=${ansible_user_input}\n"
    final_inventory_content+="ansible_ssh_private_key_file=${ssh_key_path_input}\n"
    final_inventory_content+="is_ha_cluster=$([ "$num_nodes" -gt 1 ] && echo true || echo false)\n"
    final_inventory_content+="ansible_python_interpreter=/usr/bin/python3\n"
    final_inventory_content+="controller_name=${sanitized_env_name}-controller\n"
    final_inventory_content+="model_name=landscape-${sanitized_env_name}\n\n"
    final_inventory_content+="$all_vars_section"

    echo -e "\n${TAG_INFO} Gerando o arquivo '${inventory_file}'...${RESET}"
    echo -e "$final_inventory_content" > "$inventory_file"
    echo -e "${GREEN}✓ Inventário de ${env_name_for_wizard} configurado com sucesso.${RESET}"
    pause_and_continue
}

select_inventory_to_configure() {
    while true; do
        clear; echo -e "${TITLE_COLOR}=== Selecionar Inventário para Configurar ===${RESET}"
        printf "  ${OPTION_COLOR}%-40s\n" "1) Produção (inventory/production.ini)"
        printf "  ${OPTION_COLOR}%-40s\n" "2) Homologação (inventory/homologacao.ini)"
        printf "  ${OPTION_COLOR}%-40s\n" "3) Teste (inventory/testing.ini)"
        printf "  ${OPTION_COLOR}%-40s\n" "0) Voltar ao Menu Principal"
        echo ""
        echo "---------------------------------------------------------------------"
        local choice; read -r -p "$(echo -e "${TAG_ACTION} Selecione a opção: ${RESET}")" choice
        case "$choice" in
            1) run_inventory_configurator_wizard "inventory/production.ini" "Produção"; break ;;
            2) run_inventory_configurator_wizard "inventory/homologacao.ini" "Homologação"; break ;;
            3) run_inventory_configurator_wizard "inventory/testing.ini" "Teste"; break ;;
            0) break ;;
            *) echo -e "\n${DANGER_COLOR}Opção inválida.${RESET}"; sleep 1 ;;
        esac
    done
}

select_environment() {
    while true; do
        clear; echo -e "${TITLE_COLOR}#####################################################################"
        echo "#          SETUP DO CLUSTER LANDSCAPE - v${SCRIPT_VERSION}          #"
        echo "#          SERPRO | DIOPE/SUPOP/OPDIG/OPDTV         #"
        echo -e "#####################################################################${RESET}\n"
        echo -e "${TAG_INFO} Escolha o ambiente do Landscape a ser gerenciado:"
        printf "  ${WARN_COLOR}%-30s ${DESC_COLOR}%s\n" "1) Produção" "- Ambiente ativo e crítico."
        printf "  ${OPTION_COLOR}%-30s ${DESC_COLOR}%s\n" "2) Homologação" "- Espelho da produção para validação."
        printf "  ${OPTION_COLOR}%-30s ${DESC_COLOR}%s\n" "3) Teste" "- Laboratório local para desenvolvimento."
        printf "  ${OPTION_COLOR}%-30s ${DESC_COLOR}%s\n" "4) Configurar um Inventário" "- Guia para criar/atualizar um arquivo .ini."
        printf "  ${OPTION_COLOR}%-30s ${DESC_COLOR}%s\n" "0) Sair" "- Encerrar o script."
        echo "---------------------------------------------------------------------"
        local choice; read -r -p "$(echo -e "${TAG_ACTION} Selecione a opção: ${RESET}")" choice
        case "$choice" in
            1) ENV_NAME="Produção"; INVENTORY_FILE="inventory/production.ini"; return 0 ;;
            2) ENV_NAME="Homologação"; INVENTORY_FILE="inventory/homologacao.ini"; return 0 ;;
            3) ENV_NAME="Teste"; INVENTORY_FILE="inventory/testing.ini"; return 0 ;;
            4) select_inventory_to_configure; continue ;;
            0) return 1 ;;
            *) echo -e "\n${DANGER_COLOR}Opção inválida.${RESET}"; sleep 1 ;;
        esac
    done
}

print_title_box() {
    clear
    local title_text="SETUP DO CLUSTER LANDSCAPE - AMBIENTE [${ENV_NAME}]"
    local box_width=71; local text_len=${#title_text}; local padding=$(( (box_width - text_len) / 2 ))
    echo -e "${TITLE_COLOR}"
    echo "#######################################################################"
    printf "#%*s%s%*s#\n" $padding "" "$title_text" $((box_width - padding - text_len)) ""
    echo "#######################################################################${RESET}"
}

main_menu() {
    while true; do
        print_title_box
        echo -e "${TAG_INFO} Ambiente Selecionado: ${BOLD}${ENV_NAME}${RESET}"
        if [ -n "${JUJU_MODEL_NAME-}" ]; then echo -e "${TAG_INFO} Modelo Juju: ${BOLD}${JUJU_MODEL_NAME}${RESET}"; fi
        echo "---------------------------------------------------------------------"
        echo -e "Selecione uma operação para o ambiente:"

        echo -e "\n${HEADER_COLOR}[1] Orquestração Principal${RESET}"
        printf "  ${OPTION_COLOR}%-35s %s\n" "1) Preparar Infraestrutura" "- (Ansible) Instala LXD, Juju, redes, etc."
        printf "  ${OPTION_COLOR}%-35s %s\n" "2) Implantar Aplicações" "- (Juju) Cria o controller e implanta o Landscape."

        echo -e "\n${HEADER_COLOR}[2] Diagnóstico & Operações${RESET}"
        printf "  ${OPTION_COLOR}%-35s %s\n" "4) Exibir Status do Juju" "- Mostra o status do modelo Juju."

        echo -e "\n${DANGER_COLOR}[3] Operações Destrutivas ⚠️${RESET}"
        printf "  ${DANGER_COLOR}%-35s %s\n" "8) Destruir Ambiente (Total)" "- A forma mais segura e completa de limpar o ambiente."

        echo -e "\n${HEADER_COLOR}[4] Outras Opções${RESET}"
        printf "  ${OPTION_COLOR}%-35s %s\n" "0) Voltar ao Menu Principal" "- Retorna à seleção de ambiente."

        echo "---------------------------------------------------------------------"
        local choice; read -r -p "$(echo -e "${TAG_ACTION}Escolha a opção: ${RESET}")" choice
        case "$choice" in
            1) run_playbook "macro-prepare-infra.yml" ;;
            2) run_playbook "macro-deploy-apps.yml" ;;
            4) juju status -m "${JUJU_CONTROLLER_NAME}:${JUJU_MODEL_NAME}" --watch 1s || true ;;
            8) if confirm_action "CERTEZA que deseja DESTRUIR TOTALMENTE o Ambiente ${ENV_NAME}?" && run_playbook "macro-destroy-total.yml"; then LAST_ACTION_STATUS="${GREEN}✓ Ambiente destruído.${RESET}"; else LAST_ACTION_STATUS="${RED}Ação cancelada.${RESET}"; fi ;;
            0) return ;;
            *) echo -e "\n${DANGER_COLOR}Opção inválida.${RESET}";;
        esac
        pause_and_continue
    done
}

# --- Funções de Inicialização ---
initialize_dependencies() {
    if ! command -v ansible-playbook &> /dev/null; then
        if confirm_action "Comando 'ansible-playbook' não encontrado. Instalar Ansible (requer sudo)?"; then
            sudo apt update && sudo apt install -y ansible || die "Falha ao instalar Ansible."
        else die "Ansible é necessário para continuar."; fi
    fi
    if ! command -v juju &> /dev/null; then
        if confirm_action "Comando 'juju' não encontrado. Instalar Juju (requer sudo)?"; then
            sudo snap install juju --classic || die "Falha ao instalar Juju."
        else die "Juju é necessário para continuar."; fi
    fi
    if ! command -v tmux &> /dev/null && ! command -v screen &> /dev/null; then
        echo -e "${TAG_WARN} Para execuções longas, recomenda-se usar uma sessão persistente (tmux ou screen)."
        if confirm_action "Comando 'tmux' não encontrado. Instalar agora (requer sudo)?"; then
            sudo apt update && sudo apt install -y tmux || echo -e "${WARN_COLOR}Falha ao instalar tmux. Continuando..."
        fi
    fi
}

# --- Função Principal ---
main() {
    initialize_dependencies
    while true; do
        select_environment || break
        load_env_vars_from_inventory "$INVENTORY_FILE"
        main_menu
    done
    echo -e "\n${GREEN}Encerrando o script. Até logo!${RESET}\n"
}

main
