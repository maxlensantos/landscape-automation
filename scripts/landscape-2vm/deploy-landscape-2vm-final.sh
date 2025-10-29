#!/bin/bash

################################################################################
# LANDSCAPE HA DEPLOYMENT - 2 VMs ON-PREMISE (FINAL)
# 
# VM1: 10.35.0.9 (Controller + Services/0)
# VM2: 10.35.0.10 (Services/1 Replicas)
#
# Uso: bash deploy-landscape-2vm-final.sh
# Tempo: 30-40 minutos
################################################################################

set -e

# ============================================================================
# CONFIGURAÇÃO FIXA
# ============================================================================

VM1_IP="10.35.0.9"
VM1_USER="serpro"
VM2_IP="10.35.0.10"
VM2_USER="serpro"
CONTROLLER="ha-controller"
MODEL="landscape-self-hosted"

# ============================================================================
# CORES & COLORS
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# FUNÇÕES DE LOG
# ============================================================================

log_header() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║ $1${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
    exit 1
}

progress_bar() {
    local i
    for i in {1..50}; do
        echo -n "."
        sleep 0.1
    done
    echo ""
}

# ============================================================================
# PRE-CHECKS
# ============================================================================

log_header "PRE-DEPLOYMENT CHECKS"

log_info "Verificando Juju..."
if ! command -v juju &> /dev/null; then
    log_error "Juju não está instalado. Execute: sudo snap install juju --classic"
fi
log_success "Juju instalado"

log_info "Verificando controller..."
if ! juju status -m controller &> /dev/null; then
    log_error "Controller 'ha-controller' não está acessível. Execute bootstrap primeiro."
fi
log_success "Controller acessível"

log_info "Verificando SSH para VM2 (${VM2_IP})..."
if ! ssh -o ConnectTimeout=5 ${VM2_USER}@${VM2_IP} "echo OK" &> /dev/null; then
    log_error "Falha ao conectar em ${VM2_USER}@${VM2_IP}. Configure SSH keys."
fi
log_success "SSH para VM2 OK"

log_success "Todos os pré-requisitos OK!"

# ============================================================================
# FASE 1: PREPARAR VM2
# ============================================================================

log_header "FASE 1: PREPARANDO VM2 (10.35.0.10)"

log_info "Criando diretórios SSH em VM2..."
ssh ${VM2_USER}@${VM2_IP} << 'PREP_COMMANDS'
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    echo "✓ Diretórios criados"
PREP_COMMANDS

log_success "VM2 preparada"

# ============================================================================
# FASE 2: REGISTRAR VM2 NO JUJU
# ============================================================================

log_header "FASE 2: REGISTRANDO VM2 NO JUJU"

log_info "Adicionando máquina manual em ${VM2_IP}..."
MACHINE_OUTPUT=$(juju add-machine manual/${VM2_USER}@${VM2_IP} 2>&1)
MACHINE=$(echo "$MACHINE_OUTPUT" | grep -oP "machine-\d+" || echo "machine-1")

log_success "Machine criada: $MACHINE"

log_info "Aguardando machine ficar disponível..."
progress_bar

TIMEOUT=0
while [ $TIMEOUT -lt 60 ]; do
    if juju machines -m default 2>&1 | grep -q "$MACHINE.*started"; then
        log_success "Machine $MACHINE está pronta!"
        break
    fi
    if juju machines -m default 2>&1 | grep -q "$MACHINE"; then
        log_warn "Machine em processo: $MACHINE"
    fi
    sleep 5
    TIMEOUT=$((TIMEOUT + 5))
done

if [ $TIMEOUT -ge 60 ]; then
    log_warn "Timeout aguardando machine, continuando..."
fi

# ============================================================================
# FASE 3: CRIAR MODELO
# ============================================================================

log_header "FASE 3: CRIANDO MODELO LANDSCAPE"

log_info "Verificando se modelo existe..."
if juju models 2>&1 | grep -q "^${MODEL}"; then
    log_warn "Modelo já existe, removendo..."
    juju destroy-model ${MODEL} --yes --force 2>/dev/null || true
    sleep 10
fi

log_info "Criando modelo '$MODEL'..."
juju add-model ${MODEL}

log_info "Aguardando modelo inicializar..."
progress_bar

log_success "Modelo '$MODEL' criado"

# ============================================================================
# FASE 4: CRIAR BUNDLE
# ============================================================================

log_header "FASE 4: CRIANDO BUNDLE PARA 2 VMs"

BUNDLE_FILE="/tmp/landscape-2vm-bundle-$(date +%s).yaml"

cat > ${BUNDLE_FILE} << 'BUNDLE_END'
name: landscape-scalable-2vm
description: Landscape HA Deployment for 2 VMs On-Premise
series: jammy

applications:
  haproxy:
    charm: ch:haproxy
    channel: stable
    revision: 75
    num_units: 2
    expose: true
    options:
      default_timeouts: queue 60000, connect 5000, client 120000, server 120000
      global_default_bind_options: no-tlsv10
      services: ""
      ssl_cert: SELFSIGNED

  landscape-server:
    charm: ch:landscape-server
    channel: stable
    revision: 124
    num_units: 2
    constraints: mem=2048
    options:
      landscape_ppa: ppa:landscape/self-hosted-24.04

  postgresql:
    charm: ch:postgresql
    channel: 14/stable
    revision: 468
    num_units: 2
    constraints: mem=2048
    options:
      plugin_plpython3u_enable: true
      plugin_ltree_enable: true
      plugin_intarray_enable: true
      plugin_debversion_enable: true
      plugin_pg_trgm_enable: true
      experimental_max_connections: 500

  rabbitmq-server:
    charm: ch:rabbitmq-server
    channel: 3.9/stable
    revision: 188
    num_units: 2
    options:
      consumer-timeout: 259200000

relations:
  - [landscape-server, rabbitmq-server]
  - [landscape-server, haproxy]
  - [landscape-server:db, postgresql:db-admin]
BUNDLE_END

log_success "Bundle criado: $BUNDLE_FILE"

# ============================================================================
# FASE 5: DEPLOY BUNDLE
# ============================================================================

log_header "FASE 5: FAZENDO DEPLOY DO BUNDLE"

log_info "Deploying bundle (isto pode levar 30-40 minutos)..."
echo ""

juju deploy ${BUNDLE_FILE} -m ${MODEL}

log_success "Bundle deployment iniciado"

# ============================================================================
# FASE 6: MONITORAR
# ============================================================================

log_header "FASE 6: MONITORANDO DEPLOYMENT"

log_info "Status será atualizado a cada 5 segundos"
log_info "Pressione Ctrl+C para parar o monitoramento"
echo ""

# Mostrar status inicial
juju status -m ${MODEL}

echo ""
log_warn "Continuando monitoramento... (Ctrl+C para parar)"
echo ""

# Monitorar
juju status -m ${MODEL} --watch 5s 2>/dev/null || true

# ============================================================================
# FASE 7: PÓS-DEPLOYMENT
# ============================================================================

log_header "FASE 7: COLETA DE INFORMAÇÕES"

log_info "Controller Status:"
juju status -m controller --format short 2>/dev/null || echo "N/A"

log_info "Deployment Status:"
juju status -m ${MODEL} --format short 2>/dev/null || echo "N/A"

echo ""
log_info "Aguardando estabilização final (2 minutos)..."
sleep 120

# ============================================================================
# RELATÓRIO FINAL
# ============================================================================

log_header "DEPLOYMENT LANDSCAPE HA - 2 VMs COMPLETO"

echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   ✓ LANDSCAPE HA DEPLOYMENT FINALIZADO                   ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo "TOPOLOGIA:"
echo "  VM1: ${VM1_USER}@${VM1_IP} (machine-0) - Controller + Services"
echo "  VM2: ${VM2_USER}@${VM2_IP} (machine-1) - Services Replicas"
echo ""

echo "STATUS FINAL:"
juju status -m ${MODEL}
echo ""

echo "OBTENDO IPs:"
echo ""
log_info "HAProxy (Load Balancer):"
HAPROXY_IP=$(juju run -m ${MODEL} haproxy/0 'unit-get public-address' 2>/dev/null || echo "N/A")
echo "  URL: https://${HAPROXY_IP}"
echo ""

log_info "Landscape Server:"
LS_IP=$(juju run -m ${MODEL} landscape-server/0 'unit-get public-address' 2>/dev/null || echo "N/A")
echo "  Primary: ${LS_IP}"
echo ""

log_info "PostgreSQL:"
PG_IP=$(juju run -m ${MODEL} postgresql/0 'unit-get public-address' 2>/dev/null || echo "N/A")
echo "  Primary: ${PG_IP}"
echo ""

log_info "RabbitMQ:"
RMQ_IP=$(juju run -m ${MODEL} rabbitmq-server/0 'unit-get public-address' 2>/dev/null || echo "N/A")
echo "  Primary: ${RMQ_IP}"
echo ""

echo "╔════════════════════════════════════════════════════════════╗"
echo "║                 PRÓXIMOS PASSOS                           ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "1. Aguarde até que TODOS os units estejam 'active':"
echo "   juju status -m ${MODEL} --watch 3s"
echo ""
echo "2. Acesse Landscape via HTTPS:"
echo "   https://${HAPROXY_IP}"
echo ""
echo "3. Validar deployment:"
echo "   bash scripts/landscape-2vm/validate-landscape-2vm.sh ${MODEL}"
echo ""
echo "4. Configurar SSL certificate (opcional):"
echo "   juju config haproxy ssl_cert=... ssl_key=..."
echo ""
echo "5. Configure clientes Landscape:"
echo "   sudo landscape-config -u https://${HAPROXY_IP}"
echo ""
echo "6. Teste failover:"
echo "   juju remove-unit landscape-server/0"
echo "   (O traffic redireciona para landscape-server/1)"
echo ""

log_success "Deployment finalizado com sucesso!"
echo ""
