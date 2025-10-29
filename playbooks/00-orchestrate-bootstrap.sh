#!/bin/bash
#
# Juju Bootstrap Orchestration Script
# Executa os playbooks na sequência correta com validações
#

set -e

INVENTORY="${1:-inventory/ha-test.ini}"
PLAYBOOKS_DIR="playbooks"

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Função de log
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

# Validações iniciais
validate_prerequisites() {
    log_info "Validando pré-requisitos..."
    
    if ! command -v ansible-playbook &> /dev/null; then
        log_error "ansible-playbook não encontrado"
        exit 1
    fi
    
    if ! command -v juju &> /dev/null; then
        log_error "juju não encontrado"
        exit 1
    fi
    
    if [ ! -f "$INVENTORY" ]; then
        log_error "Inventory não encontrado: $INVENTORY"
        exit 1
    fi
    
    log_success "Pré-requisitos validados"
}

# FASE 1: Limpeza
cleanup_previous() {
    log_info "FASE 1: Limpeza de bootstrap anterior..."
    
    if [ -f "${PLAYBOOKS_DIR}/99-nuke-juju.yml" ]; then
        ansible-playbook -i "$INVENTORY" \
            "${PLAYBOOKS_DIR}/99-nuke-juju.yml" \
            --extra-vars "ansible_user_warnings=False" \
            || log_warning "Limpeza parcial (erros esperados)"
        
        log_success "Ambiente limpo"
        sleep 10
    fi
}

# FASE 2: Estratégia de acesso à rede
network_strategy() {
    log_info "FASE 2: Aplicando estratégia de acesso à rede..."
    
    if [ -f "${PLAYBOOKS_DIR}/00-network-access-strategy.yml" ]; then
        ansible-playbook -i "$INVENTORY" \
            "${PLAYBOOKS_DIR}/00-network-access-strategy.yml" \
            -vv \
            || {
                log_error "Falha na estratégia de rede"
                return 1
            }
        
        log_success "Estratégia de rede aplicada"
        sleep 5
    fi
}

# FASE 3: Bootstrap
bootstrap() {
    log_info "FASE 3: Executando Juju Bootstrap..."
    
    if [ -f "${PLAYBOOKS_DIR}/01-bootstrap-juju-manual-FIXED.yml" ]; then
        ansible-playbook -i "$INVENTORY" \
            "${PLAYBOOKS_DIR}/01-bootstrap-juju-manual-FIXED.yml" \
            -vv \
            || {
                log_error "Bootstrap falhou"
                return 1
            }
        
        log_success "Bootstrap completado com sucesso"
        sleep 10
    fi
}

# FASE 4: Validação
validate() {
    log_info "FASE 4: Validando resultado..."
    
    # Testar conectividade do controller
    if ! ansible -i "$INVENTORY" ha-node-01 -m shell -a 'juju list-controllers' &> /dev/null; then
        log_error "Juju controller não respondendo"
        return 1
    fi
    
    # Verificar status
    if ! ansible -i "$INVENTORY" ha-node-01 -m shell -a 'juju status' &> /dev/null; then
        log_error "Juju status falhou"
        return 1
    fi
    
    log_success "Bootstrap validado com sucesso"
}

# Main execution
main() {
    echo ""
    echo "======================================="
    echo "Juju Bootstrap Orchestration"
    echo "======================================="
    echo ""
    
    validate_prerequisites
    
    log_info "Iniciando bootstrap com inventory: $INVENTORY"
    echo ""
    
    cleanup_previous || {
        log_warning "Continuando apesar de erros na limpeza..."
    }
    
    network_strategy || {
        log_error "Estratégia de rede falhou"
        exit 1
    }
    
    bootstrap || {
        log_error "Bootstrap falhou"
        exit 1
    }
    
    validate || {
        log_error "Validação falhou"
        exit 1
    }
    
    echo ""
    echo "======================================="
    log_success "BOOTSTRAP CONCLUÍDO COM SUCESSO!"
    echo "======================================="
    echo ""
    
    ansible -i "$INVENTORY" ha-node-01 -m shell -a 'juju status'
}

# Executar
main "$@"
