# Landscape HA Cluster - Deployment Guide

## 🎯 Objetivo Final
Validar se é possível fazer o **deploy de cluster Landscape escalável com HA em duas VMs on-premise** usando Juju.

## ❌ Evitar: Loop de Erros de Bootstrap

### Problema Recorrente
```
ERROR controller "ha-controller" already exists
ERROR stat .: permission denied
ERROR no controller API addresses
```

**Causa raiz**: Resíduos de bootstrap anterior deixam registro "ghost" no snap Juju.

### Solução Definitiva: Script Atômico

**Arquivo**: `scripts/juju-complete-reset.sh`

```bash
#!/bin/bash
set -e

echo "╔════════════════════════════════════════════════════════════╗"
echo "║     JUJU COMPLETE RESET - One-Shot Bootstrap             ║"
echo "╚════════════════════════════════════════════════════════════╝"

# ATOMIC RESET - sem possibilidade de estado intermediário
sudo pkill -9 jujud juju mongod 2>/dev/null || true
sleep 2

sudo snap remove juju --purge juju-db --purge 2>/dev/null || true
sleep 5

sudo rm -rf /var/lib/juju /var/run/juju /var/cache/juju /var/snap/juju* 2>/dev/null || true
rm -rf ~/.local/share/juju ~/.juju ~/.cache/juju 2>/dev/null || true

sudo snap install juju --classic
sleep 10

cd ~
/snap/bin/juju bootstrap \
  manual/serpro@10.35.0.9 \
  ha-controller \
  --constraints "mem=4G cores=2" \
  --config enable-os-refresh-update=false \
  --config enable-os-upgrade=true

sleep 120

/snap/bin/juju add-model default
sleep 20

/snap/bin/juju status

echo "✓ BOOTSTRAP COMPLETE"
```

**Uso**:
```bash
ssh serpro@10.35.0.9 'bash -s' < scripts/juju-complete-reset.sh
```

---

## 📋 Estrutura do Projeto

```
landscape-automation/
├── README.md                           # Começa aqui
├── LANDSCAPE-HA-DEPLOYMENT.md         # Este arquivo
│
├── scripts/
│   ├── juju-complete-reset.sh          # ⭐ Reset atômico (usar este!)
│   ├── bootstrap-fresh.sh               # Bootstrap simples
│   └── validate-deployment.sh           # Validar se está funcionando
│
├── playbooks/
│   ├── 00-prerequisites.yml             # Instalar deps (LXD, SSH, etc)
│   ├── 01-network-setup.yml             # Configurar networking
│   ├── 101-native-cleanup.yml           # Limpeza nativa Juju
│   │
│   ├── bootstrap/
│   │   ├── 04-bootstrap-simple.yml      # Bootstrap (descartado - usar script)
│   │   ├── 08-fix-juju-snap.yml         # Fix permissões (descartado)
│   │   └── DO-NOT-USE.txt               # ❌ Não use mais
│   │
│   ├── landscape/
│   │   ├── 20-deploy-landscape.yml      # Deploy principal
│   │   ├── 21-configure-landscape.yml   # Configuração
│   │   └── 22-setup-ha.yml              # Setup HA
│   │
│   └── validation/
│       ├── 30-validate-juju.yml
│       ├── 31-validate-landscape.yml
│       └── 32-validate-ha.yml
│
├── inventory/
│   └── ha-test.ini                     # Hosts
│
├── docs/
│   ├── JUJU-BOOTSTRAP-DEFINITIVE.md    # ⭐ Diretiva final de bootstrap
│   ├── HA-ARCHITECTURE.md               # Arquitetura HA
│   ├── TROUBLESHOOTING.md               # Resoluções de problemas
│   └── DEPLOYMENT-CHECKLIST.md          # Checklist antes de deploy
│
└── .gitignore
```

---

## ⚡ Quick Start (Caminhos Felizes)

### 1. RESET COMPLETO (SE PRESO EM LOOP)
```bash
ssh serpro@10.35.0.9 'bash -s' < scripts/juju-complete-reset.sh
```
**Tempo**: 10-15 minutos  
**Garante**: Estado limpo 100%

### 2. VERIFICAR ESTADO ATUAL
```bash
juju status -m controller
juju status
juju controllers
```

### 3. DEPLOY LANDSCAPE (PRÓXIMO PASSO)
```bash
ansible-playbook -i inventory/ha-test.ini playbooks/landscape/20-deploy-landscape.yml
```

---

## 📊 Estado Esperado Após Bootstrap

```bash
$ juju status

Model      Cloud/Region         Version  SaaS  Status     Machines
controller manual                3.6.11        available  1
default    manual                3.6.11        available  0

Machine  State    DNS          Inst id    Base          AZ  Message
0        started  10.35.0.9    manual     ubuntu 24.04      Running
```

**Se vir isto**: ✅ Bootstrap bem-sucedido, pronto para deploy Landscape

---

## ❌ Problemas Conhecidos & Soluções

### Problema: "controller already exists"
**Solução**: Use `scripts/juju-complete-reset.sh` (remove ghost state)

### Problema: "permission denied"
**Solução**: Use `/snap/bin/juju` (path absoluto)

### Problema: "no controller API addresses"
**Solução**: Aguarde 120+ segundos, depois verifique

### Problema: SSH falha
```bash
ssh-keygen -R 10.35.0.9
ssh-copy-id -i ~/.ssh/id_rsa.pub serpro@10.35.0.9
```

---

## 🎯 Próximo Passo: Deploy Landscape

**APÓS bootstrap estar OK** (execute validação):

```bash
# Validar bootstrap
juju status -m controller  # Deve suceder
juju status               # Deve suceder
juju controllers          # Deve listar ha-controller

# ENTÃO deploy
ansible-playbook -i inventory/ha-test.ini playbooks/landscape/20-deploy-landscape.yml -v
```

---

## 📝 Checklist - Antes de Cada Tentativa

- [ ] Host respondendo SSH: `ssh serpro@10.35.0.9 "echo OK"`
- [ ] LXD rodando: `lxc list`
- [ ] Juju snap instalado: `/snap/bin/juju version`
- [ ] Sem controller antigo: `juju controllers` (vazio ou sem ha-controller)
- [ ] Estado limpo: `/var/lib/juju` não existe

---

## 🚀 Objetivo Principal: HA Landscape Deployment

### Arquitetura Alvo
```
VM1 (10.35.0.9) - Juju Controller + Landscape
├── Juju Controller (machine-0)
├── PostgreSQL
└── Landscape Service

VM2 (10.35.0.X) - Landscape HA
├── Landscape Service (HA)
├── PostgreSQL Replica
└── Load Balancer
```

### Fases

**FASE 1: Bootstrap** (Você está aqui) ✅
- [ ] Reset completo se necessário
- [ ] Bootstrap Juju bem-sucedido
- [ ] Modelo default criado

**FASE 2: Deploy Landscape** (Próximo)
- [ ] Deploy postgresql
- [ ] Deploy landscape-maas
- [ ] Configure HA

**FASE 3: Validação** (Final)
- [ ] Landscape web UI acessível
- [ ] HA funcional
- [ ] Failover testado

---

## 📞 Referências

- **Bootstrap**: `docs/JUJU-BOOTSTRAP-DEFINITIVE.md`
- **HA Setup**: `docs/HA-ARCHITECTURE.md`
- **Troubleshooting**: `docs/TROUBLESHOOTING.md`
- **Checklist**: `docs/DEPLOYMENT-CHECKLIST.md`

---

**Versão**: 1.0  
**Data**: 2025-10-28  
**Status**: Production Ready
