#!/bin/bash
#
# setup.sh: Ponto de entrada para automação da implantação do Landscape.
#

# Aborta o script se um comando falhar, se uma variável não estiver definida ou em erros de pipe.
set -euo pipefail

# --- Paleta de Cores e Estilos ---
if command -v tput >/dev/null && tput setaf 1 >/dev/null 2>&1; then
    # Cores
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    RED=$(tput setaf 1)
    BLUE=$(tput setaf 4)
    
    # Estilos
    BOLD=$(tput bold)
    RESET=$(tput sgr0)
    
    # Tags de Nível de Severidade
    TAG_INFO="${BLUE}[INFO]${RESET}"
    TAG_WARN="${YELLOW}[WARN]${RESET}"
    TAG_CRITICAL="${RED}[CRITICAL]${RESET}"
    TAG_ACTION="${BLUE}[ACTION]${RESET}"

    # Cores para UI
    TITLE_COLOR="${BOLD}${BLUE}"
    HEADER_COLOR="${GREEN}"
    PROMPT_COLOR="${BLUE}"
    OPTION_COLOR="${BOLD}"
    DESC_COLOR="${RESET}"
    WARN_COLOR="${YELLOW}"
    DANGER_COLOR="${RED}"
else # Fallback
    GREEN="\033[1;32m"
    YELLOW="\033[1;33m"
    RED="\033[1;31m"
    BLUE="\033[1;34m"
    BOLD="\033[1m"
    RESET="\033[0m"
    TAG_INFO="[INFO]"
    TAG_WARN="[WARN]"
    TAG_CRITICAL="[CRITICAL]"
    TAG_ACTION="[ACTION]"
    TITLE_COLOR="${BOLD}${BLUE}"
    HEADER_COLOR="${GREEN}"
    PROMPT_COLOR="${BLUE}"
    OPTION_COLOR="${BOLD}"
    DESC_COLOR="${RESET}"
    WARN_COLOR="${YELLOW}"
    DANGER_COLOR="${RED}"
fi

VAULT_PASS_FILE="../vault_pass.txt"
ENV_NAME=""
INVENTORY_FILE=""

# --- Funções Auxiliares ---

die() {
    echo -e "${DANGER_COLOR}ERRO: $1${RESET}" >&2
    exit 1
}

confirm_action() {
    local prompt="$1"
    local response
    read -p "$(echo -e "${TAG_ACTION} ${WARN_COLOR}${prompt} [digite 'sim' para confirmar]: ${RESET}")" response
    response=${response,,}
    if [[ "$response" == "sim" ]]; then
        return 0
    else
        echo -e "${RED}Ação cancelada.${RESET}"
        return 1
    fi
}

pause_and_continue() {
    echo -e "${DESC_COLOR}"
    read -p "Pressione [Enter] para voltar ao menu..."
    echo -e "${RESET}"
}

is_playbook_implemented() {
    local playbook_file="playbooks/$1"
    if [ -f "$playbook_file" ] && ! grep -q "ainda não implementado" "$playbook_file"; then
        return 0
    else
        return 1
    fi
}

run_playbook() {
    local playbook_file="$1"
    local extra_args=("${@:2}")
    
    if ! is_playbook_implemented "$playbook_file"; then
        echo -e "${WARN_COLOR}Aviso: O Playbook 'playbooks/${playbook_file}' não está implementado.${RESET}"
        return 1
    fi

    echo -e "\n${PROMPT_COLOR}Executando o playbook: ${playbook_file} no ambiente: ${ENV_NAME}${RESET}"
    
    local vault_args=()
    if [ -f "$VAULT_PASS_FILE" ]; then
        vault_args=("--vault-password-file" "$VAULT_PASS_FILE")
    fi
    
    if ansible-playbook -i "${INVENTORY_FILE}" "playbooks/${playbook_file}" "${vault_args[@]}" "${extra_args[@]}"; then
        echo -e "${GREEN}✓ Playbook '${playbook_file}' concluído com sucesso.${RESET}"
        return 0
    else
        echo -e "${DANGER_COLOR}✗ ERRO: O playbook '${playbook_file}' falhou.${RESET}"
        return 1
    fi
}

# --- Funções de UI e Menu ---

select_environment() {
    while true; do
        clear
        echo -e "${TITLE_COLOR}"
        echo "#####################################################################"
        echo "#                                                                   #"
        echo "#                  SETUP DO CLUSTER LANDSCAPE                       #"
        echo "#                                                                   #"
        echo "#####################################################################"
        echo -e "${RESET}"

        echo -e "${TAG_INFO} Selecione o ambiente que deseja gerenciar."
        echo ""
        echo -e "  ${OPTION_COLOR}1)${DESC_COLOR} Produção"
        echo -e "  ${OPTION_COLOR}2)${DESC_COLOR} Teste"
        echo -e "  ${OPTION_COLOR}3)${DESC_COLOR} Sobre & Contato"
        echo -e "  ${OPTION_COLOR}4)${DESC_COLOR} Sair"
        echo ""
        echo "---------------------------------------------------------------------"
        echo -e "${DESC_COLOR}SERPRO | DIOPE/SUPOP/OPDIG/OPDTV${RESET}"
        echo "---------------------------------------------------------------------"

        local choice
        read -p "$(echo -e "${TAG_ACTION} Selecione a opção desejada: ${RESET}")" choice
        case "$choice" in
            1)
                ENV_NAME="Produção"
                INVENTORY_FILE="inventory/production.ini"
                return 0
                ;; 
            2)
                ENV_NAME="Teste"
                INVENTORY_FILE="inventory/testing.ini"
                return 0
                ;; 
            3)
                clear
                echo -e "${TITLE_COLOR}"
                echo "#####################################################################"
                echo "#                                                                   #"
                echo "#             SOBRE A FERRAMENTA DE SETUP DO LANDSCAPE              #"
                echo "#                                                                   #"
                echo "#####################################################################"
                echo -e "${RESET}"
                echo -e "    ${TAG_INFO} Utilitário para automação da implantação e gerenciamento"
                echo -e "           dos clusters do Canonical Landscape."
                echo ""
                echo -e "    ---------------------------------------------------------------"
                echo ""
                echo -e "      Versão           : 2.0 (Estável)"
                echo -e "      Mantenedores     : Equipe OPDTV | DIOPE/SUPOP/OPDIG"
                echo -e "      Empresa          : SERPRO"
                echo -e "      Canal de Suporte : lista-supop-opdig-opdtv @grupos.serpro.gov.br"
                echo ""
                echo -e "    ---------------------------------------------------------------"
                echo ""
                read -p "$(echo -e "    ${TAG_ACTION} Pressione [Enter] para voltar ao menu principal... █ ${RESET}")"
                ;; 
            4)
                exit 0
                ;; 
            *)
                echo -e "\n${DANGER_COLOR}Opção inválida. Por favor, tente novamente.${RESET}"
                sleep 1
                ;; 
        esac
    done
}

print_title_box() {
    clear
    local title_text="SETUP DO CLUSTER LANDSCAPE - AMBIENTE [${ENV_NAME}]"
    local box_width=71
    local text_len=${#title_text}
    local padding=$(( (box_width - text_len) / 2 ))

    echo -e "${TITLE_COLOR}"
    echo "#######################################################################"
    echo "#                                                                     #"
    printf "#%*s%s%*s#\n" $padding "" "$title_text" $((box_width - padding - text_len)) ""
    echo "#                                                                     #"
    echo "#######################################################################"
    echo -e "${RESET}"
}

advanced_menu() {
    while true; do
        print_title_box
        echo -e "${BLUE}Menu de Ações Manuais (Avançado)${RESET}"
        echo "-----------------------------------------------------"
        
        declare -a actions
        if is_playbook_implemented "02-bootstrap-juju.yml"; then actions+=("Instalar Juju"); fi
        if is_playbook_implemented "03-deploy-application.yml"; then actions+=("Implantar Aplicação"); fi
        if is_playbook_implemented "05-post-config.yml"; then actions+=("Aplicar Pós-Config"); fi
        actions+=("Voltar ao Menu Principal")

        for i in "${!actions[@]}"; do
            printf "  ${OPTION_COLOR}%2d)${DESC_COLOR} %s\n" "$((i+1))" "${actions[i]}"
        done
        echo "-----------------------------------------------------"

        local choice
        read -p "$(echo -e "${TAG_ACTION} Selecione a opção avançada: ${RESET}")" choice

        if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#actions[@]}" ]; then
            echo -e "\n${DANGER_COLOR}Opção inválida.${RESET}"; continue
        fi

        local action="${actions[$choice-1]}"

        case "$action" in
            "Instalar Juju") run_playbook "02-bootstrap-juju.yml"; pause_and_continue; ;;
            "Implantar Aplicação") run_playbook "03-deploy-application.yml"; pause_and_continue; ;;
            "Aplicar Pós-Config") run_playbook "05-post-config.yml"; pause_and_continue; ;;
            "Voltar ao Menu Principal") return ;; 
        esac
    done
}

main_menu() {
    while true; do
        print_title_box
        echo -e "${TAG_INFO} Selecione uma operação para o cluster."

        # Ações de Ciclo de Vida
        if [ "$ENV_NAME" == "Teste" ]; then
            echo -e "\n${HEADER_COLOR}-- Ciclo de Vida --${RESET}"
            printf "  ${OPTION_COLOR}%s${DESC_COLOR}\n     %s %s\n" "1) Implantar Cluster (Primeira Vez)" "${TAG_INFO}" "Cria um novo cluster em ambiente limpo."
            printf "  ${OPTION_COLOR}%s${DESC_COLOR}\n     %s %s\n" "2) Reconstruir Cluster (Ação Destrutiva)" "${TAG_WARN}" "O cluster existente será DEMOLIDO antes da recriação."
        fi

        echo -e "\n${HEADER_COLOR}-- Diagnóstico --${RESET}"
        printf "  ${OPTION_COLOR}%s${DESC_COLOR}\n     %s %s\n" "3) Verificar Status do Ambiente" "${TAG_INFO}" "Exibe o status dos modelos e aplicações Juju."
        printf "  ${OPTION_COLOR}%s${DESC_COLOR}\n     %s %s\n" "4) Executar Health Check" "${TAG_INFO}" "Executa verificação detalhada da saúde do cluster."

        echo -e "\n${DANGER_COLOR}-- Operações Destrutivas --${RESET}"
        printf "  ${DANGER_COLOR}%s${DESC_COLOR}\n     %s %s\n" "5) Demolir Cluster" "${TAG_CRITICAL}" "Ação irreversível. Remove todos os recursos do cluster."
        printf "  ${DANGER_COLOR}%s${DESC_COLOR}\n     %s %s\n" "6) Forçar Demolição (Recuperação)" "${TAG_CRITICAL}" "Usar apenas se a demolição normal falhar. Risco de recursos órfãos."

        echo -e "\n${HEADER_COLOR}-- Outras Opções --${RESET}"
        printf "  ${OPTION_COLOR}%s${DESC_COLOR}\n" "7) Menu de Ações Manuais (Avançado)"
        printf "  ${OPTION_COLOR}%s${DESC_COLOR}\n" "8) Sair"
        echo "---------------------------------------------------------------------"
        echo -e "${DESC_COLOR}SERPRO | DIOPE/SUPOP/OPDIG/OPDTV${RESET}"
        echo "---------------------------------------------------------------------"

        local choice
        read -p "$(echo -e "${TAG_ACTION} Selecione a opção desejada: ${RESET}")" choice

        case "$choice" in
            1)  # Implantar
                if [ "$ENV_NAME" != "Teste" ]; then echo -e "${DANGER_COLOR}Opção inválida.${RESET}"; pause_and_continue; continue; fi
                run_playbook "00-prepare-vms.yml" && run_playbook "01-setup-cluster-lxd.yml" && run_playbook "02-bootstrap-juju.yml" && run_playbook "03-deploy-application.yml" && run_playbook "98-verify-health.yml" && run_playbook "06-expose-proxy.yml" || echo -e "${DANGER_COLOR}A macro falhou.${RESET}"
                pause_and_continue; ;;
            2)  # Reconstruir
                if [ "$ENV_NAME" != "Teste" ]; then echo -e "${DANGER_COLOR}Opção inválida.${RESET}"; pause_and_continue; continue; fi
                if confirm_action "RECONSTRUIR irá DEMOLIR e recriar o Cluster ${ENV_NAME}."; then
                    run_playbook "99-destroy-application.yml" && run_playbook "00-prepare-vms.yml" && run_playbook "01-setup-cluster-lxd.yml" && run_playbook "02-bootstrap-juju.yml" && run_playbook "03-deploy-application.yml" && run_playbook "98-verify-health.yml" && run_playbook "06-expose-proxy.yml" || echo -e "${DANGER_COLOR}A macro falhou.${RESET}"
                fi
                pause_and_continue; ;;
            3)  # Verificar Status
                local model_name=$(grep -E '^model_name=' "${INVENTORY_FILE}" | cut -d'=' -f2)
                local exit_code=0
                sg lxd -c "juju status -m '${model_name}'" || exit_code=$?
                if [ $exit_code -ne 0 ]; then
                    echo -e "\n${WARN_COLOR}----------------------------------------------------------------------"
                    echo -e "AVISO: O comando 'juju status' falhou (código: $exit_code)."
                    echo -e "\n${TAG_INFO} Se a mensagem de erro acima for 'model not found', significa que o"
                    echo -e "       ambiente '${model_name}' não existe ou já foi destruído."
                    echo -e "----------------------------------------------------------------------${RESET}"
                fi
                pause_and_continue; ;;
            4)  # Health Check
                run_playbook "98-verify-health.yml"; pause_and_continue; ;;
            5)  # Demolir
                if confirm_action "Você tem CERTEZA que deseja DEMOLIR o Cluster ${ENV_NAME}?"; then
                    run_playbook "99-destroy-application.yml"
                fi
                pause_and_continue; ;;
            6)  # Forçar Demolição
                if confirm_action "AÇÃO CRÍTICA. Confirma a demolição forçada do Cluster ${ENV_NAME}?"; then
                    echo -e "${DANGER_COLOR}--- Executando Demolição Forçada ---${RESET}"
                    local model_name=$(grep -E '^model_name=' "${INVENTORY_FILE}" | cut -d'=' -f2)
                    sg lxd -c "juju destroy-model '${model_name}' --force --destroy-storage --no-prompt" || echo -e "${WARN_COLOR}Falha ao forçar a demolição (o modelo pode já ter sido removido).${RESET}"
                fi
                pause_and_continue; ;;
            7) advanced_menu; ;; 
            8) exit 0; ;; 
            *) echo -e "\n${DANGER_COLOR}Opção inválida.${RESET}"; pause_and_continue; ;; 
esac
    done
}

# --- Ponto de Entrada do Script ---
main() {
    if [ ! -d "playbooks" ] || [ ! -d "inventory" ]; then
        die "Este script deve ser executado a partir do diretório raiz 'landscape-automation'."
    fi
    select_environment
    main_menu
}

main "$@"
