#!/bin/bash
set -e

INVENTORY="${1:-inventory/ha-test.ini}"
PLAYBOOKS_DIR="playbooks"

# Cores
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Bootstrap com Limpeza Nativa (Abordagem Final)          ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ETAPA 1: Limpeza Nativa
echo -e "${YELLOW}[1/2] Executando limpeza nativa do Juju...${NC}"
ansible-playbook -i "$INVENTORY" \
  "${PLAYBOOKS_DIR}/101-native-cleanup.yml" \
  -vv

echo -e "${GREEN}✓ Limpeza nativa concluída${NC}"
echo ""

# ETAPA 2: Bootstrap
echo -e "${YELLOW}[2/2] Executando Juju Bootstrap...${NC}"
ansible-playbook -i "$INVENTORY" \
  "${PLAYBOOKS_DIR}/03-full-bootstrap-orchestration.yml" \
  -vv

echo -e "${GREEN}✓ Bootstrap concluído${NC}"
echo ""

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║            ✓ SEQUÊNCIA CONCLUÍDA COM SUCESSO!             ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
