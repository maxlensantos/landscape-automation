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

ENV_NAME=""
INVENTORY_FILE=""
LAST_ACTION_STATUS=""

# --- Funções Auxiliares ---

die() {
    echo -e "${DANGER_COLOR}ERRO: $1${RESET}" >&2
    exit 1
}

confirm_action() {
    local prompt="$1"
    local response
    read -p "$(echo -e "${TAG_ACTION} ${WARN_COLOR}${prompt} [s/N]: ${RESET}")" response
    response=${response:-N}
    if [[ "$response" =~ ^[Ss]$ ]]; then
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
    # Valida o ticket do sudo uma vez antes de começar.
    sudo -v

    local playbook_file="$1"
    local extra_playbook_args=("${@:2}")
    
    if ! is_playbook_implemented "$playbook_file"; then
        echo -e "${WARN_COLOR}Aviso: O Playbook 'playbooks/${playbook_file}' não está implementado.${RESET}"
        return 1
    fi

    echo -e "\n${PROMPT_COLOR}Executando o playbook: ${playbook_file} no ambiente: ${ENV_NAME}${RESET}"
    
    # Salva qualquer trap EXIT que já exista.
    local old_trap
    old_trap=$(trap -p EXIT)

    # Inicia um loop de keep-alive para o sudo APENAS durante a execução do playbook.
    while true; do sudo -n true; sleep 60; done &>/dev/null &
    local SUDO_KEEPALIVE_PID=$!
    # Garante que o keep-alive seja morto mesmo se o usuário cancelar (Ctrl+C).
    trap "kill $SUDO_KEEPALIVE_PID &>/dev/null" EXIT

    # Prepara os argumentos para o ansible-playbook
    local ansible_args=()
    if grep -q "\$ANSIBLE_VAULT;" "vars/secrets.yml" 2>/dev/null; then
        if [ -f "$VAULT_PASS_FILE" ]; then
            ansible_args+=("--vault-password-file" "$VAULT_PASS_FILE")
        elif [ -n "${TEMP_VAULT_FILE-}" ]; then
            ansible_args+=("--vault-password-file" "$TEMP_VAULT_FILE")
        else
            ansible_args+=("--ask-vault-pass")
        fi
    fi
    
    local playbook_exit_code=0
    ansible-playbook -i "${INVENTORY_FILE}" "playbooks/${playbook_file}" "${ansible_args[@]}" "${extra_playbook_args[@]}" || playbook_exit_code=$?

    # Para o processo de keep-alive e restaura o trap original.
    kill $SUDO_KEEPALIVE_PID &>/dev/null
    eval "$old_trap" # Restaura o trap que existia antes.

    if [ $playbook_exit_code -eq 0 ]; then
        echo -e "${GREEN}✓ Playbook '${playbook_file}' concluído com sucesso.${RESET}"
        return 0
    else
        echo -e "${DANGER_COLOR}✗ ERRO: O playbook '${playbook_file}' falhou.${RESET}"
        return 1
    fi
}

# --- Funções de UI e Menu ---

print_light_header() {
    clear
    echo -e "${TITLE_COLOR}=== SETUP DO CLUSTER LANDSCAPE | Ambiente: [${ENV_NAME}] ===${RESET}"
    echo ""
}

select_environment() {
    while true; do
        clear
        echo -e "${TITLE_COLOR}"
        echo "#####################################################################"
        echo "#            SETUP DO CLUSTER LANDSCAPE - v${SCRIPT_VERSION}                     #"
        echo "#             SERPRO | DIOPE/SUPOP/OPDIG/OPDTV             #"
        echo "#####################################################################"
        echo -e "${RESET}"

        echo -e "${TAG_INFO} Escolha o ambiente do Landscape a ser gerenciado:"
        echo ""
        printf "  ${WARN_COLOR}%-25s ${DESC_COLOR}%s\n" "⚠️ 1) Produção" "- Ambiente ativo e crítico."
        printf "  ${OPTION_COLOR}%-25s ${DESC_COLOR}%s\n" "2) Teste" "- Ambiente de homologação."
        printf "  ${OPTION_COLOR}%-25s ${DESC_COLOR}%s\n" "3) Informações" "- Sobre e Contato."
        printf "  ${OPTION_COLOR}%-25s ${DESC_COLOR}%s\n" "4) Sair" "- Encerrar o script."
        echo ""
        echo "---------------------------------------------------------------------"

        local choice
        read -p "$(echo -e "${TAG_ACTION} Selecione a opção desejada: ${RESET}")" choice

        case "$choice" in
            1)
                local prod_confirm
                read -p "$(echo -e "\n${TAG_ACTION} ${WARN_COLOR}Você selecionou o ambiente de PRODUÇÃO. Esta ação é crítica. Deseja continuar? (s/N): ${RESET}")" prod_confirm
                prod_confirm=${prod_confirm:-N}
                if [[ "$prod_confirm" =~ ^[Ss]$ ]]; then
                    ENV_NAME="Produção"
                    INVENTORY_FILE="inventory/production.ini"
                    return 0
                else
                    echo -e "${RED}Ação cancelada.${RESET}"
                    sleep 1
                    continue
                fi
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
                echo -e "      Versão           : ${SCRIPT_VERSION} (Estável)"
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
        print_light_header
        echo -e "${BLUE}Tarefas Avançadas – Administração Manual${RESET}"
        echo "-----------------------------------------------------"

        if [ -n "$LAST_ACTION_STATUS" ]; then
            echo -e "[INFO] Última ação: $LAST_ACTION_STATUS\n"
            LAST_ACTION_STATUS=""
        fi

        echo -e "${HEADER_COLOR}[Configuração]${RESET}"
        printf "  ${OPTION_COLOR}%-40s\n" "⚙️ 1) Instalar Juju"
        printf "  ${OPTION_COLOR}%-40s\n" "🚀 2) Implantar Aplicação"
        printf "  ${OPTION_COLOR}%-40s\n" "🧩 3) Executar Pós-Configuração"
        echo ""

        echo -e "${HEADER_COLOR}[Integração]${RESET}"
        printf "  ${OPTION_COLOR}%-40s\n" "🔐 4) Aplicar Certificado PFX"
        printf "  ${OPTION_COLOR}%-40s\n" "🌐 5) Ativar Integração OIDC"
        printf "  ${OPTION_COLOR}%-40s\n" "⛔ 6) Desativar Integração OIDC"
        echo ""

        echo -e "${HEADER_COLOR}[Rede e Segurança]${RESET}"
        printf "  ${OPTION_COLOR}%-40s\n" "🛡️ 7) Aplicar Firewall Básico"
        echo ""

        echo -e "${HEADER_COLOR}[Sistema]${RESET}"
        printf "  ${OPTION_COLOR}%-40s\n" "↩️ 8) Voltar ao Menu Principal"
        echo "-----------------------------------------------------"

        local choice
        read -p "$(echo -e "${TAG_ACTION}Escolha a opção desejada: ${RESET}")" choice

        case "$choice" in
            1) 
                if confirm_action "Executar a instalação do Juju?"; then
                    if run_playbook "02-bootstrap-juju.yml"; then LAST_ACTION_STATUS="${GREEN}✓ Sucesso: Juju instalado.${RESET}"; else LAST_ACTION_STATUS="${DANGER_COLOR}✗ Falha: Instalação do Juju.${RESET}"; fi
                fi
                pause_and_continue; ;;
            2) 
                if confirm_action "Executar a implantação da aplicação?"; then
                    if run_playbook "03-deploy-application.yml"; then LAST_ACTION_STATUS="${GREEN}✓ Sucesso: Aplicação implantada.${RESET}"; else LAST_ACTION_STATUS="${DANGER_COLOR}✗ Falha: Implantação da Aplicação.${RESET}"; fi
                fi
                pause_and_continue; ;;
            3) 
                if confirm_action "Executar a pós-configuração?"; then
                    if run_playbook "05-post-config.yml"; then LAST_ACTION_STATUS="${GREEN}✓ Sucesso: Pós-configuração aplicada.${RESET}"; else LAST_ACTION_STATUS="${DANGER_COLOR}✗ Falha: Pós-configuração.${RESET}"; fi
                fi
                pause_and_continue; ;;
            4) 
                if confirm_action "Aplicar o certificado PFX? Esta ação pode ser disruptiva."; then
                    if run_playbook "07-apply-pfx-cert.yml"; then LAST_ACTION_STATUS="${GREEN}✓ Sucesso: Certificado PFX aplicado.${RESET}"; else LAST_ACTION_STATUS="${DANGER_COLOR}✗ Falha: Aplicação do certificado PFX.${RESET}"; fi
                fi
                pause_and_continue; ;;
            5) 
                if confirm_action "Ativar a integração OIDC? Esta ação pode ser disruptiva."; then
                    if run_playbook "10-enable-oidc.yml"; then LAST_ACTION_STATUS="${GREEN}✓ Sucesso: Integração OIDC ativada.${RESET}"; else LAST_ACTION_STATUS="${DANGER_COLOR}✗ Falha: Ativação do OIDC.${RESET}"; fi
                fi
                pause_and_continue; ;;
            6) 
                if confirm_action "Desativar a integração OIDC? Esta ação pode ser disruptiva."; then
                    if run_playbook "11-disable-oidc.yml"; then LAST_ACTION_STATUS="${GREEN}✓ Sucesso: Integração OIDC desativada.${RESET}"; else LAST_ACTION_STATUS="${DANGER_COLOR}✗ Falha: Desativação do OIDC.${RESET}"; fi
                fi
                pause_and_continue; ;;
            7) 
                if confirm_action "Aplicar as regras de firewall? Isso pode impactar a conectividade."; then
                    if run_playbook "09-harden-firewall.yml"; then LAST_ACTION_STATUS="${GREEN}✓ Sucesso: Firewall aplicado.${RESET}"; else LAST_ACTION_STATUS="${DANGER_COLOR}✗ Falha: Aplicação do firewall.${RESET}"; fi
                fi
                pause_and_continue; ;;
            8) return ;;
            *) echo -e "\n${DANGER_COLOR}Opção inválida.${RESET}"; pause_and_continue; ;;
        esac
    done
}
main_menu() {
    while true; do
        print_title_box
        echo -e "${TAG_INFO} SERPRO | DIOPE/SUPOP/OPDIG/OPDTV"
        echo -e "${TAG_INFO} Ambiente Selecionado: ${BOLD}${ENV_NAME}${RESET}"
        echo "---------------------------------------------------------------------"
        echo -e "Selecione uma operação para o ambiente:"
        echo ""

        if [ "$ENV_NAME" == "Teste" ]; then
            echo -e "${HEADER_COLOR}[1] Ciclo de Vida do Ambiente${RESET}"
            printf "  ${OPTION_COLOR}%-35s ${DESC_COLOR}%s\n" "1) Implantar Cluster" "- Cria um novo cluster limpo."
            printf "  ${OPTION_COLOR}%-35s ${DESC_COLOR}%s\n" "2) Reconstruir Cluster" "- Remove e recria o cluster de teste."
            echo ""
        fi

        echo -e "${HEADER_COLOR}[2] Diagnóstico${RESET}"
        printf "  ${OPTION_COLOR}%-35s ${DESC_COLOR}%s\n" "3) Exibir Status do Ambiente" "- Mostra o status Juju atual."
        printf "  ${OPTION_COLOR}%-35s ${DESC_COLOR}%s\n" "4) Verificar Certificado HAProxy" "- Exibe validade e detalhes do certificado."
        printf "  ${OPTION_COLOR}%-35s ${DESC_COLOR}%s\n" "5) Executar Health Check" "- Avalia a integridade do cluster."
        echo ""

        echo -e "${DANGER_COLOR}[3] Operações Destrutivas ⚠️${RESET}"
        printf "  ${DANGER_COLOR}%-35s ${DESC_COLOR}%s\n" "6) Destruir Ambiente (IRREVERSÍVEL)" "- Remove completamente o ambiente."
        echo ""

        echo -e "${HEADER_COLOR}[4] Outras Opções${RESET}"
        printf "  ${OPTION_COLOR}%-35s ${DESC_COLOR}%s\n" "7) Tarefas Avançadas (Manuais)" "- Submenu de ações granulares."
        printf "  ${OPTION_COLOR}%-35s ${DESC_COLOR}%s\n" "8) Sair" "- Encerra o script."
        echo "---------------------------------------------------------------------"

        local choice
        read -p "$(echo -e "${TAG_ACTION}Escolha a opção desejada: ${RESET}")" choice

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
            4)  # Verificar Certificado
                run_playbook "08-verify-certificate.yml"; pause_and_continue; ;;
            5)  # Health Check
                run_playbook "98-verify-health.yml"; pause_and_continue; ;;
            6)  # Demolir
                if confirm_action "Você tem CERTEZA que deseja DESTRUIR o Ambiente ${ENV_NAME} (IRREVERSÍVEL)?"; then
                    run_playbook "99-destroy-application.yml"
                fi
                pause_and_continue; ;;
            7) advanced_menu; ;;
            8) exit 0; ;;
            *) echo -e "\n${DANGER_COLOR}Opção inválida.${RESET}"; pause_and_continue; ;;
esac
    done
}
# --- Ponto de Entrada do Script ---

ensure_persistent_session() {
    # Se o script for chamado com um marcador interno, não faça nada para evitar loop infinito.
    if [[ "${1-}" == "--no-tmux-wrap" ]]; then
        shift
        return 0
    fi

    # Se já estivermos em tmux ou screen, não faça nada.
    if [ -n "${TMUX-}" ] || [ -n "${STY-}" ]; then
        return 0
    fi

    # Verifica se existe uma sessão tmux destacada com o nome esperado.
    if command -v tmux &> /dev/null && tmux has-session -t "landscape-automation" 2>/dev/null; then
        echo -e "${TAG_INFO} Encontrei uma sessão 'tmux' existente chamada 'landscape-automation'." >&2
        read -p "$(echo -e "${TAG_ACTION} Deseja se reconectar a ela? (S/n): ${RESET}")" response
        response=${response:-S}
        if [[ "$response" =~ ^[Ss]$ ]]; then
            echo -e "${GREEN}Reconectando à sessão 'tmux'...${RESET}"
            sleep 1
            exec tmux attach-session -t "landscape-automation"
        fi
    # Senão, verifica se existe uma sessão screen
    elif command -v screen &> /dev/null && screen -ls | grep -q "\.landscape-automation\s"; then
        echo -e "${TAG_INFO} Encontrei uma sessão 'screen' existente chamada 'landscape-automation'." >&2
        read -p "$(echo -e "${TAG_ACTION} Deseja se reconectar a ela? (S/n): ${RESET}")" response
        response=${response:-S}
        if [[ "$response" =~ ^[Ss]$ ]]; then
            echo -e "${GREEN}Reconectando à sessão 'screen'...${RESET}"
            sleep 1
            exec screen -r "landscape-automation"
        fi
    fi

    # Se não houver sessão para reconectar, ou o usuário disse não, oferece para criar uma nova.
    echo -e "${TAG_WARN} AVISO: Nenhuma sessão ativa encontrada. Sua sessão atual não é persistente." >&2
    echo -e "${TAG_INFO} A execução de playbooks longos pode ser interrompida se sua conexão SSH cair." >&2
    read -p "$(echo -e "${TAG_ACTION} Deseja iniciar uma nova sessão segura com 'tmux'? (S/n): ${RESET}")" response
    response=${response:-S} # Padrão para Sim

    if [[ ! "$response" =~ ^[Ss]$ ]]; then
        echo -e "${TAG_INFO} Ok, continuando sem uma sessão persistente. Cuidado com desconexões!${RESET}"
        sleep 2
        return 0
    fi

    # Tenta usar tmux primeiro, se não, screen como fallback.
    if command -v tmux &> /dev/null; then
        echo -e "${GREEN}Iniciando dashboard com 'tmux'...${RESET}"
        sleep 1
        tmux new-session -s "landscape-automation" "$0 --no-tmux-wrap" \; \
             split-window -v "juju status --watch 1s" \; \
             select-pane -t 0
        exit 0 # Sai do script pai para deixar o tmux controlar o terminal
    elif command -v screen &> /dev/null; then
        echo -e "${GREEN}TMUX não encontrado. Iniciando sessão simples com 'screen'...${RESET}"
        sleep 1
        screen -S "landscape-automation" "$0" "$@"
        exit 0 # Sai do script pai para deixar o screen controlar o terminal
    else
        # Se nenhum dos dois for encontrado, oferece para instalar o tmux
        echo -e "${TAG_WARN}AVISO: Nem 'tmux' nem 'screen' foram encontrados para criar uma sessão segura.${RESET}" >&2
        read -p "$(echo -e "${TAG_ACTION}Deseja instalar o 'tmux' (recomendado) agora? (S/n): ${RESET}")" install_response
        install_response=${install_response:-S}

        if [[ "$install_response" =~ ^[Ss]$ ]]; then
            echo -e "${TAG_INFO}Instalando o tmux...${RESET}"
            if sudo apt update && sudo apt install -y tmux; then
                echo -e "${GREEN}TMUX instalado com sucesso! Reiniciando o script dentro da nova sessão...${RESET}"
                sleep 2
                exec tmux new-session -s "landscape-automation" "$0 --no-tmux-wrap" \; \
                     split-window -v "juju status --watch 1s" \; \
                     select-pane -t 0
            else
                echo -e "${DANGER_COLOR}Falha ao instalar o tmux. Por favor, instale manualmente e execute o script novamente.${RESET}"
                exit 1
            fi
        else
            echo -e "${TAG_INFO}Ok, continuando sem uma sessão persistente. Cuidado com desconexões!${RESET}"
            sleep 2
            return 0
        fi
    fi
}

main() {
    # Garante que o script rode em uma sessão persistente
    ensure_persistent_session "$@"

    # Valida a senha do sudo no início para evitar múltiplos prompts
    echo -e "${TAG_ACTION} A execução pode exigir privilégios de administrador (sudo).${RESET}"
    sudo -v
    echo ""

    # Lida com a senha do Vault de forma centralizada
    if grep -q "\$ANSIBLE_VAULT;" "vars/secrets.yml" 2>/dev/null && [ ! -f "$VAULT_PASS_FILE" ]; then
        read -s -p "Vault password: " VAULT_PASSWORD_VAR
        echo
        TEMP_VAULT_FILE=$(mktemp)
        echo "$VAULT_PASSWORD_VAR" > "$TEMP_VAULT_FILE"
        # Garante que o arquivo temporário seja limpo ao sair
        trap 'rm -f "$TEMP_VAULT_FILE"' EXIT
        export TEMP_VAULT_FILE
    fi

    if [ ! -d "playbooks" ] || [ ! -d "inventory" ]; then
        die "Este script deve ser executado a partir do diretório raiz 'landscape-automation'."
    fi
    select_environment
    main_menu
}

main "$@"
