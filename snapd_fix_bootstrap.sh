#!/bin/bash
set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_section() {
    echo -e "\n${YELLOW}=== $1 ===${NC}\n"
}

# ============================================================================
log_section "1. Iniciando Reparo Completo do Snapd"
# ============================================================================

log_info "Parando e desabilitando serviços snap..."
sudo systemctl stop snapd snapd.socket 2>/dev/null || true
sudo systemctl stop snapd.apparmor 2>/dev/null || true
sleep 3

log_info "Desabilitando serviços snap..."
sudo systemctl disable snapd snapd.socket 2>/dev/null || true
sleep 2

log_info "Purgando snapd via apt (remove configs do sistema)..."
sudo apt purge -y snapd 2>/dev/null || true
sudo apt autoremove -y --purge 2>/dev/null || true
sleep 2

log_info "Desmontando volumes snap..."
sudo umount -l /snap/* 2>/dev/null || true
sudo umount -l /var/snap/* 2>/dev/null || true
sleep 2

log_info "Removendo diretórios residuais..."
sudo rm -rf /snap /var/snap /var/lib/snapd /var/cache/snapd ~/snap /etc/apparmor.d/usr.lib.snapd* 2>/dev/null || true
sleep 2

log_info "Limpeza de diretórios concluída."

# ============================================================================
log_section "2. Reinstalando Snapd"
# ============================================================================

log_info "Atualizando índice de pacotes..."
sudo apt update

log_info "Instalando snapd..."
sudo apt install -y snapd

log_info "Aguardando 60s para snapd inicializar e estabilizar..."
for i in {60..1}; do
    echo -ne "\rAguardando: ${i}s  "
    sleep 1
done
echo ""

# ============================================================================
log_section "3. Verificando Funcionalidade do Snapd"
# ============================================================================

log_info "Testando instalação do hello-world..."
if sudo snap install hello-world; then
    log_info "✅ Teste do hello-world OK - Snapd está funcional"
    sudo snap remove -y hello-world || true
else
    log_error "FALHA ao instalar hello-world"
    log_error "Possíveis causas:"
    log_error "  - Snapd ainda corrompido"
    log_error "  - Sem conexão com internet"
    log_error "  - Proxy/firewall bloqueando acesso à snap store"
    log_error "  - DNS não resolvendo corretamente"
    exit 1
fi

# ============================================================================
log_section "4. Instalando Juju e LXD"
# ============================================================================

log_info "Instalando Juju (--classic)..."
sudo snap install juju --classic
sleep 20

log_info "Instalando LXD..."
sudo snap install lxd
sleep 20

log_info "Adicionando usuário ao grupo lxd..."
sudo usermod -aG lxd $(whoami) || true

# ============================================================================
log_section "5. Inicializando LXD"
# ============================================================================

log_info "Inicializando LXD com configuração automática..."
sudo lxd init --auto
sleep 10

log_info "Verificando status do LXD..."
sudo lxc list || log_warn "LXD ainda pode estar inicializando"

# ============================================================================
log_section "6. Executando Juju Bootstrap"
# ============================================================================

log_info "Executando Juju Bootstrap para 'ha-controller'..."
cd ~

/snap/bin/juju bootstrap manual/$(whoami)@10.35.0.9 ha-controller \
    --constraints "mem=4G cores=2" \
    --config enable-os-refresh-update=false \
    --config enable-os-upgrade=false

log_info "Aguardando 120s para controller estabilizar..."
for i in {120..1}; do
    echo -ne "\rAguardando: ${i}s  "
    sleep 1
done
echo ""

# ============================================================================
log_section "7. Configurando Models e Verificação Final"
# ============================================================================

log_info "Adicionando modelo 'default'..."
/snap/bin/juju add-model default
sleep 15

log_info "Aguardando 30s para model estar pronto..."
sleep 30

log_info "Status Final do Juju:"
/snap/bin/juju status

log_info "Status Final do LXD:"
sudo lxc list

# ============================================================================
log_section "✅ Script de Reparo e Bootstrap Concluído com Sucesso!"
# ============================================================================

log_info "Próximos passos recomendados:"
log_info "  1. Verifique: /snap/bin/juju status"
log_info "  2. Verifique: sudo lxc list"
log_info "  3. Deploy uma aplicação de teste se necessário"