#!/bin/bash

# lib/helpers.sh: Funções auxiliares e definições de estilo para o script principal.

# Aborta o script se um comando falhar, se uma variável não estiver definida ou em erros de pipe.
set -euo pipefail

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

# --- Funções Auxiliares ---
die() { echo -e "${DANGER_COLOR}ERRO: $1${RESET}" >&2; exit 1; }
confirm_action() { local prompt="$1"; local response; read -r -p "$(echo -e "${TAG_ACTION} ${WARN_COLOR}${prompt} [s/N]: ${RESET}")" response; response=${response:-N}; if [[ "$response" =~ ^[Ss]$ ]]; then return 0; else echo -e "${RED}Ação cancelada.${RESET}"; return 1; fi; }
pause_and_continue() { echo -e "${DESC_COLOR}"; read -r -p "Pressione [Enter] para continuar..." && echo -e "${RESET}" || echo -e "${RESET}"; }
is_playbook_implemented() { local playbook_file="playbooks/$1"; if [ -f "$playbook_file" ] && ! grep -q "ainda não implementado" "$playbook_file"; then return 0; else return 1; fi; }
