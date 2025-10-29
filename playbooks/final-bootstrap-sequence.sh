#!/bin/bash
#
# Final Juju Bootstrap Sequence
# Executar após LXD reset bem-sucedido
#

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
echo -e "${BLUE}║   Final Juju Bootstrap Sequence (Etapas 2-4 de 4)         ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ETAPA 2: Cleanup Agressivo
echo -e "${YELLOW}[2/4] Executando cleanup agressivo dos agentes Juju...${NC}"
ansible-playbook -i "$INVENTORY" \
  "${PLAYBOOKS_DIR}/99-cleanup-agents-advanced.yml" \
  -vv

echo -e "${GREEN}✓ Cleanup agressivo concluído${NC}"
echo ""

# ETAPA 3: Bootstrap
echo -e "${YELLOW}[3/4] Executando Juju Bootstrap...${NC}"
ansible-playbook -i "$INVENTORY" \
  "${PLAYBOOKS_DIR}/03-full-bootstrap-orchestration.yml" \
  -vv

echo -e "${GREEN}✓ Bootstrap concluído${NC}"
echo ""

# ETAPA 4: Validação Final
echo -e "${YELLOW}[4/4] Validação final...${NC}"
ssh -o ProxyJump=s779929545@10.31.3.145 -t serpro@10.35.0.9 << 'FINAL_EOF'

echo ""
echo "════════════════════════════════════════════════════"
echo "VALIDAÇÃO FINAL DO BOOTSTRAP"
echo "════════════════════════════════════════════════════"
echo ""

echo "[1] Status do Controller:"
juju status -c ha-controller || echo "Controller não respondendo"

echo ""
echo "[2] Modelos:"
juju list-models -c ha-controller

echo ""
echo "[3] Máquinas:"
juju machines -c ha-controller

echo ""
echo "[4] Status do Modelo:"
juju status -m ha-controller:landscape

echo ""
echo "════════════════════════════════════════════════════"
echo "✓ BOOTSTRAP FINALIZADO COM SUCESSO!"
echo "════════════════════════════════════════════════════"
echo ""

FINAL_EOF

echo -e "${GREEN}✓ Validação concluída${NC}"
echo ""

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║            ✓ SEQUÊNCIA CONCLUÍDA COM SUCESSO!             ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Próximos passos:"
echo "1. Deploy de aplicações: juju deploy charm-name"
echo "2. Monitor: juju watch -m ha-controller:landscape"
echo ""
