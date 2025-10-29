#!/bin/bash
set -e

echo "╔════════════════════════════════════════════════════════════╗"
echo "║     VALIDAÇÃO DE CONECTIVIDADE - Ha-Test Inventory       ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

KEYFILE="/home/s779929545/.ssh/id_ed25519"
JUMP_HOST="s779929545@10.31.3.145"
TARGET_HOST="serpro@10.35.0.9"

# TEST 1: Conexão Direta
echo "[TEST 1/5] Testando SSH DIRETO (sem jump)..."
if timeout 10 ssh -i "$KEYFILE" -o ConnectTimeout=5 serpro@10.35.0.9 "echo OK" &>/dev/null; then
    echo "✓ DIRETO OK - Você pode remover o ProxyJump"
else
    echo "✗ DIRETO FALHOU - Você PRECISA do ProxyJump"
fi

echo ""

# TEST 2: Conexão via Jump
echo "[TEST 2/5] Testando SSH via JUMP HOST..."
if timeout 10 ssh -i "$KEYFILE" -o ProxyJump="$JUMP_HOST" -o ConnectTimeout=5 serpro@10.35.0.9 "echo OK" &>/dev/null; then
    echo "✓ JUMP OK - ProxyJump está funcionando"
else
    echo "✗ JUMP FALHOU - Verifique a chave e o bastion"
fi

echo ""

# TEST 3: Juju
echo "[TEST 3/5] Testando Juju..."
if /snap/bin/juju version &>/dev/null; then
    echo "✓ JUJU OK - Version: $(/snap/bin/juju version 2>&1 | head -1)"
else
    echo "✗ JUJU FALHOU - Instale: sudo snap install juju --classic"
fi

echo ""

# TEST 4: Ansible Inventory
echo "[TEST 4/5] Testando Ansible Inventory..."
if ansible-inventory -i inventory/ha-test.ini --host ha-node-01 &>/dev/null; then
    echo "✓ INVENTORY OK"
else
    echo "✗ INVENTORY FALHOU - Verifique ha-test.ini"
fi

echo ""

# TEST 5: Ansible Ping
echo "[TEST 5/5] Testando Ansible Ping para ha-node-01..."
if timeout 30 ansible -i inventory/ha-test.ini ha-node-01 -m ping 2>&1 | grep -q "SUCCESS"; then
    echo "✓ ANSIBLE PING OK"
else
    echo "✗ ANSIBLE PING FALHOU - Há problema de conectividade"
fi

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                   RESUMO DOS TESTES                        ║"
echo "╚════════════════════════════════════════════════════════════╝"
```

---

## 🎯 Depois dos Testes, Reporte:

Compartilhe aqui os resultados dos **5 testes** e vou te dar a **configuração final exata** para seu ambiente.
```
[TEST 1] DIRETO:   [ ] OK  [ ] FALHOU
[TEST 2] JUMP:     [ ] OK  [ ] FALHOU  
[TEST 3] JUJU:     [ ] OK  [ ] FALHOU
[TEST 4] INVENTORY:[ ] OK  [ ] FALHOU
[TEST 5] PING:     [ ] OK  [ ] FALHOU
