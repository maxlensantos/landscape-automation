# Guia Arquitetural: DevOps HA com Juju e Ansible
## Para Assistentes de Código Aprender Preventivamente

---

## 1️⃣ PRINCÍPIOS FUNDAMENTAIS

### 1.1 Regra de Ouro: "Data Locality & Control Locality"

```
REGRA: O serviço deve rodar onde os dados estão.
       O controle deve estar perto do serviço.

❌ ERRADO:
Laptop (s779929545) → SSH bastion → ha-node-01 
→ Tenta rodar Juju → Impossível acessar Juju remoto

✅ CORRETO:
Laptop → SSH bastion → ha-node-01 (dentro do nó) → Juju local
         (orquestradora: Ansible)
```

### 1.2 Camadas de Abstração

```
CAMADA 1: Seu Laptop (Orquestrador)
├─ Ferramenta: Ansible, Terraform
├─ Responsabilidade: Decidir O QUÊ fazer
└─ Comunicação: SSH via bastion

CAMADA 2: Nós HA (Executores)
├─ Ferramentas: Juju, LXD, Docker
├─ Responsabilidade: FAZER (executar)
└─ Comunicação: Local (nó-para-nó)

CAMADA 3: Containers/VMs (Workloads)
├─ Ferramentas: Aplicações
├─ Responsabilidade: Rodar serviços
└─ Comunicação: Rede interna (10.35.0.0/24)
```

---

## 2️⃣ TOPOLOGIA HA CORRETA

### 2.1 Física

```
┌─────────────────────────────────────────────────────────┐
│ BASTION (10.31.3.145)                                   │
│ └─ Gateway para rede interna 10.35.0.0/24               │
└──────────────────────┬──────────────────────────────────┘
                       │ SSH jump
        ┌──────────────┴──────────────┐
        │                             │
┌───────▼────────────┐       ┌────────▼────────────┐
│ HA-NODE-01         │       │ HA-NODE-02          │
│ 10.35.0.9          │       │ 10.35.0.10          │
├────────────────────┤       ├─────────────────────┤
│ Juju Controller ✓  │       │ Juju Agent          │
│ LXD ✓              │◄─────►│ LXD ✓               │
│ Ansible Runner     │ LAN   │ Ansible Runner      │
│ (serpro@)          │       │ (serpro@)           │
└────────────────────┘       └─────────────────────┘
```

### 2.2 Lógica

```
RESPONSABILIDADES CLARAS:

ha-node-01 (10.35.0.9):
  ├─ Juju Controller (master)
  ├─ Gerencia ha-node-02 como máquina
  ├─ API em :17070 (acessível localmente)
  └─ SSH accessible via bastion

ha-node-02 (10.35.0.10):
  ├─ Juju Agent (escravo)
  ├─ Executa workloads
  ├─ Comunica com controller em ha-node-01
  └─ SSH accessible via bastion

Seu Laptop:
  ├─ Executa Ansible playbooks
  ├─ Provisiona infraestrutura
  ├─ Valida deployments
  └─ Nunca instancia Juju localmente
```

---

## 3️⃣ PADRÕES DE EXECUÇÃO

### 3.1 Pattern: "Command Execution Context"

```yaml
# ❌ ERRADO - Executar em contexto errado
- name: Deploy aplicação
  hosts: localhost  # ← ERRADO!
  tasks:
    - name: Juju deploy
      shell: juju deploy postgresql  # Não sabe de qual controller!

# ✅ CORRETO - Executar no contexto correto
- name: Deploy aplicação
  hosts: ha_nodes  # ← CORRETO!
  tasks:
    - name: Juju deploy no nó
      shell: |
        export JUJU_DATA=~/.local/share/juju
        juju deploy postgresql -m production
```

### 3.2 Pattern: "SSH Jump for Remote Execution"

```bash
# ❌ ERRADO - Tenta SSH sem jump
ssh serpro@10.35.0.9 "juju controllers"
# Falha: 10.35.0.9 não é rota direto do laptop

# ✅ CORRETO - SSH com jump
ssh -o ProxyJump=bastion serpro@10.35.0.9 "juju controllers"

# ✅ MELHOR - Ansible faz isso automaticamente
# (inventory já tem ProxyJump configurado)
ansible-playbook -i inventory playbooks/deploy.yml
```

### 3.3 Pattern: "Check vs Set"

```yaml
# ❌ ERRADO - Assumir que vai funcionar
- name: Add model
  shell: juju add-model production
  # Pode falhar silenciosamente!

# ✅ CORRETO - Verificar estado antes
- name: Check if model exists
  shell: juju models | grep -q "production"
  register: model_exists
  failed_when: false

- name: Add model (if not exists)
  shell: juju add-model production
  when: model_exists.rc != 0
```

---

## 4️⃣ CHECKLIST PREVENTIVO

### 4.1 Antes de Escrever Qualquer Playbook

```
◻ 1. Mapeou a topologia física?
   └─ Bastion → Nós → Containers

◻ 2. Definiu onde cada serviço roda?
   └─ Juju: em qual nó?
   └─ Ansible: em qual host do inventory?
   └─ Aplicações: em qual container?

◻ 3. Definiu as rotas de comunicação?
   └─ Laptop → Bastion → Nó?
   └─ Nó-A → Nó-B (LAN direta)?
   └─ Container → Container (LXD bridge)?

◻ 4. Configurou credenciais corretamente?
   └─ SSH keys distribuídas?
   └─ ProxyJump configurado?
   └─ Usuários corretos (serpro, ubuntu)?

◻ 5. Testou conectividade?
   └─ ping bastion?
   └─ ssh -o ProxyJump=bastion node?
   └─ juju controllers (no nó)?

◻ 6. Documentou suposições?
   └─ "Assume bastion em 10.31.3.145"
   └─ "Assume rede interna 10.35.0.0/24"
   └─ "Assume usuário serpro com sudo"
```

### 4.2 Ao Escrever Playbooks

```
◻ 1. Sempre execute em contexto correto
   └─ hosts: ha_nodes (não localhost)

◻ 2. Sempre especifique -m (modelo) para Juju
   └─ juju status -m default
   └─ juju deploy charm -m production

◻ 3. Sempre configure JUJU_DATA
   └─ export JUJU_DATA=~/.local/share/juju

◻ 4. Sempre trate erros gracefully
   └─ ignore_errors: true (quando apropriado)
   └─ register + conditional

◻ 5. Sempre teste isoladamente
   └─ --tags para executar partes
   └─ --limit para host específico

◻ 6. Sempre documente a intención
   └─ name: descriptivo
   └─ comments explicando por quê
```

---

## 5️⃣ ANTI-PATTERNS (O QUE EVITAR)

### 5.1 Comunicação

```
❌ Ansible rodando em localhost tentando falar com Juju remoto
❌ Juju em ha-node-01 tentando provisionar ha-node-02 sem bastion
❌ Usuário ubuntu quando devia ser serpro (ou vice-versa)
❌ SSH direto para 10.35.0.x sem ProxyJump
```

### 5.2 Estado

```
❌ Não limpar estado anterior (rm -rf ~/.local/share/juju/*)
❌ Não verificar se recurso já existe antes de criar
❌ Não esperar estabilização (sleep/retry)
❌ Não capturar saída para debug
```

### 5.3 Configuração

```
❌ StrictHostKeyChecking=yes em ambiente dinâmico
❌ UserKnownHostsFile=/etc/ssh/known_hosts (read-only)
❌ Não configurar timeout em operações lentas
❌ Não usar environment variables (JUJU_DATA, etc)
```

---

## 6️⃣ TEMPLATES DE REFERÊNCIA

### 6.1 Playbook Correto (Template)

```yaml
---
- name: Deploy via Juju HA Cluster
  hosts: ha_nodes  # ← Executar NOS nós!
  serial: 1  # ← Um de cada vez para HA
  remote_user: serpro  # ← Usuário correto
  
  vars:
    juju_data_dir: "{{ ansible_env.HOME }}/.local/share/juju"
    controller_model: "production"
  
  tasks:
    # 1. Verificar conectividade
    - name: Test Juju connectivity
      shell: juju controllers
      environment:
        JUJU_DATA: "{{ juju_data_dir }}"
      register: juju_check
      changed_when: false
    
    # 2. Criar modelo se não existir
    - name: Add model
      shell: |
        juju models | grep -q {{ controller_model }} || \
        juju add-model {{ controller_model }}
      environment:
        JUJU_DATA: "{{ juju_data_dir }}"
      when: inventory_hostname == "ha-node-01"  # ← Apenas controller
    
    # 3. Deploy com tratamento de erros
    - name: Deploy charm
      shell: |
        juju deploy postgresql -m {{ controller_model }}
      environment:
        JUJU_DATA: "{{ juju_data_dir }}"
      register: deploy_result
      retries: 3  # ← Tentar de novo se falhar
      delay: 10
      until: deploy_result.rc == 0
      when: inventory_hostname == "ha-node-01"
    
    # 4. Aguardar estabilização
    - name: Wait for deployment
      shell: |
        for i in {1..60}; do
          if juju status -m {{ controller_model }} | grep -q "active"; then
            exit 0
          fi
          sleep 5
        done
        exit 1
      environment:
        JUJU_DATA: "{{ juju_data_dir }}"
      timeout: 600
      when: inventory_hostname == "ha-node-01"
```

### 6.2 Inventory Correto (Template)

```ini
[ha_nodes]
ha-node-01 ansible_host=10.35.0.9 ansible_user=serpro
ha-node-02 ansible_host=10.35.0.10 ansible_user=serpro

[ha_nodes:vars]
# ← CRÍTICO: Comunicação remota via bastion
ansible_ssh_common_args='-o ProxyJump=bastion-serpro -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
ansible_pipelining=True
ansible_python_interpreter=/usr/bin/python3
```

---

## 7️⃣ PRINCÍPIOS DE APRENDIZADO PARA IA

### 7.1 Quando Sugerir Playbooks

```
✅ SEMPRE pergunte:
   "Em qual nó deve executar: localhost ou ha_nodes?"
   "Qual modelo Juju: controller ou production?"
   "Precisa de ProxyJump? (rede remota via bastion)"
   "Já existe esse recurso? (check antes de create)"

❌ NUNCA assuma:
   "Vou rodar em localhost"
   "Vou assumir modelo padrão"
   "SSH direto deve funcionar"
   "Primeiro acesso sempre sucede"
```

### 7.2 Quando Gerar Código

```
Pergunte ANTES de gerar:

1. "Qual é a topologia de rede?"
   → Resposta determina ProxyJump

2. "Onde os serviços rodam?"
   → Resposta determina hosts: (hosts)

3. "Qual o estado atual?"
   → Resposta determina idempotência

4. "Como tratar falhas?"
   → Resposta determina retries/rescue

5. "Qual usuário/credencial?"
   → Resposta determina autenticação
```

---

## 8️⃣ EXEMPLO DE CONVERSA CORRETA

### ❌ Conversa Ruim

```
USER: "Cria um playbook Juju"
IA: "Aqui está:" [gera playbook genérico com hosts: localhost]
```

### ✅ Conversa Boa

```
USER: "Cria um playbook Juju"

IA: "Perfeito! Preciso esclarecer a arquitetura:
    1. Onde o Juju controller deve rodar? (qual nó?)
    2. A rede está atrás de bastion? (sim/não)
    3. Qual usuário SSH? (serpro/ubuntu/outro)
    4. Qual modelo Juju? (controller/production/outro)
    5. Precisa de HA? (serial: 1)"

USER: "ha-node-01, sim bastion, serpro, production, sim"

IA: [gera playbook com hosts: ha_nodes, 
     ProxyJump, serpro, -m production, serial: 1]
```

---

## 9️⃣ RESUMO RÁPIDO

### Para o Assistente Lembrar

```
ARQUITETURA HA JUJU:

Seu Laptop (Orquestrador)
    ├─ Executa: Ansible
    ├─ Não instancia: Juju, Docker, LXD
    └─ Comunica via: SSH + bastion

ha-node-01 (Executor Principal)
    ├─ Executa: Juju Controller + Ansible
    ├─ Controla: ha-node-02
    └─ Comunica: LAN interna + SSH bastion

ha-node-02 (Executor Secundário)
    ├─ Executa: Juju Agent + Workloads
    ├─ Controlado por: ha-node-01
    └─ Comunica: LAN interna + SSH bastion

REGRA DE OURO:
"Services rodam PERTO dos dados.
 Controle roda PERTO dos serviços.
 Orquestração roda FORA da rede."
```

---

## 🔟 COMANDO MÁGICO DE VALIDAÇÃO

```bash
# Use isto para validar qualquer arquitetura:

echo "1. Bastion OK?" && \
  ssh s779929545@10.31.3.145 "echo ✓" && \

echo "2. ha-node-01 OK?" && \
  ssh -o ProxyJump=s779929545@10.31.3.145 serpro@10.35.0.9 "echo ✓" && \

echo "3. ha-node-02 OK?" && \
  ssh -o ProxyJump=s779929545@10.31.3.145 serpro@10.35.0.10 "echo ✓" && \

echo "4. Juju OK?" && \
  ssh -o ProxyJump=s779929545@10.31.3.145 serpro@10.35.0.9 "juju controllers" && \

echo "✅ ARQUITETURA VALIDADA!"
```