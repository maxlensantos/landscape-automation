# Evolução da Estratégia de Implantação do Landscape HA (26 de Outubro de 2025)

Este documento detalha a evolução da estratégia de implantação de um cluster Landscape em Alta Disponibilidade (HA) em dois nós on-premise, utilizando a abordagem de "Manual Cloud" do Juju.

## Jornada de Depuração e Descobertas Significativas

A jornada de hoje revelou a complexidade da orquestração Juju/Ansible em ambientes on-premise e a importância de alinhar a automação com as capacidades e idiossincrasias do Juju.

### 1. Incompatibilidade do Modo `ansible-playbook --check`
*   **Problema:** Playbooks falhavam em modo `--check` devido a variáveis Juju não populadas (ex: `models_json.stdout` vazio).
*   **Solução:** Implementação de lógica robusta com `default('{}')` e condições `when` para lidar com variáveis indefinidas em dry-runs.

### 2. Problemas de Ambiente Ansible (`community.general` Collection)
*   **Problema:** Módulo `community.general.juju_model` não encontrado, apesar de `ansible-galaxy` indicar instalação.
*   **Diagnóstico:** Múltiplas versões da coleção instaladas em diferentes caminhos, e `ansible-playbook` não encontrando a versão correta.
*   **Solução:** Criação de `ansible.cfg` no projeto com `collections_path = /home/serpro/.ansible/collections` (após correção de erro de digitação `collections_paths` -> `collections_path`).

### 3. Falha Fundamental: Ausência de Bootstrap do Juju Controller
*   **Problema:** O playbook mestre não incluía a etapa `juju bootstrap`, levando a erros de "no controller registered".
*   **Solução:** Criação do playbook `00-bootstrap-controller.yml` e sua inclusão na sequência correta do `macro-deploy-all.yml`.

### 4. Inconsistências na Sintaxe da CLI do Juju 3.6
*   **Problema:** Flags como `-c` e `-m` eram inconsistentes entre subcomandos Juju (`models` vs. `status`/`deploy` vs. `wait-for`).
*   **Solução:** Consulta à documentação oficial e correção da sintaxe para:
    *   `juju status -m controller:model`
    *   `juju deploy -m controller:model`
    *   `juju wait-for model <model_name>` (argumento posicional)

### 5. Problemas de Caminho de Arquivo em Comandos Remotos (Snap Confinement)
*   **Problema:** `juju add-cloud` falhava com "no such file or directory" ao referenciar `manual-cloud.yaml`.
*   **Diagnóstico:** Confinamento do Snap do Juju impedia acesso a `/tmp`. O arquivo precisava estar no diretório home do usuário.
*   **Solução:** Copiar `manual-cloud.yaml` para `/home/serpro/manual-cloud.yaml` no nó remoto.

### 6. Idempotência da `juju add-cloud`
*   **Problema:** `juju add-cloud` falhava com "cloud already exists".
*   **Solução:** Implementação de lógica "criar ou atualizar" usando `juju add-cloud` e `juju update-cloud --client -f <arquivo>`.

### 7. Erro de Bootstrap em "Manual Cloud": `region not valid`
*   **Problema:** `juju bootstrap on-premise-manual/user@host` falhava com "region not valid".
*   **Solução:** A especificação do host para uma nuvem manual deve ser feita no arquivo `manual-cloud.yaml` via `endpoint: user@host`. O comando `bootstrap` é então simplificado para `juju bootstrap <cloud_name> <controller_name>`.

### 8. Falha do Contêiner do Controlador Juju (`broken pipe`)
*   **Problema:** O contêiner do controlador Juju falhava logo após o bootstrap, com erro de "broken pipe", indicando falta de recursos.
*   **Solução:** Adição de `--constraints "mem=4G"` ao comando `juju bootstrap`.

### 9. Problemas de Timing e Idempotência do LXD
*   **Problema:** `lxd init` falhava com "connection refused" mesmo após `wait_for`.
*   **Solução:** Implementação de inicialização robusta do LXD: `snap remove --purge lxd`, `snap install lxd --channel=5.0/stable`, `wait_for` socket, `lxd init --auto --storage-backend dir`.

### 10. Idempotência da `juju add-machine`
*   **Problema:** `juju add-machine` falhava com "machine is already provisioned".
*   **Solução:** Implementação de lógica de idempotência robusta para `add-machine`, verificando `hostname` na saída de `juju machines --format=json`.

### 11. Erro de Sintaxe em Playbooks (`when` no nível do Play)
*   **Problema:** Condição `when` aplicada no nível do Play, em vez de no nível da Task, causando erro de sintaxe YAML.
*   **Solução:** Mover a condição `when` para cada Task individualmente.

### 12. Erro de Deploy de Bundle (`cannot use -n when specifying a placement directive`)
*   **Problema:** `juju deploy landscape-scalable` falhava ao tentar usar `--to lxd:0 -n 3` (ou similar) com o bundle.
*   **Diagnóstico:** Bundles não permitem a especificação de `num_units` (`-n`) junto com diretivas de posicionamento (`--to`). O Juju tenta provisionar máquinas automaticamente, o que falha em uma nuvem manual.
*   **Estratégia Corrigida:** Abandonar o deploy do bundle `landscape-scalable` e implantar cada charm individualmente, especificando o posicionamento (`--to lxd:0`, `--to lxd:1`) e as relações. Esta é a estratégia atual que o projeto está sendo refatorado para seguir.

---

## Estratégia de Implantação Atual: Manual Cloud com Deploy Individual de Charms

A estratégia atual para o cluster Landscape HA em 2 nós on-premise é baseada na "Manual Cloud" do Juju, com a implantação individual de cada charm e controle explícito sobre o posicionamento das unidades em máquinas LXC pré-provisionadas.

### Arquitetura

*   **Nós Físicos:** Duas VMs (`ha-node-01` e `ha-node-02`) atuam como hosts para contêineres LXD.
*   **Juju Controller:** Co-localizado em `ha-node-01`.
*   **Cloud:** `on-premise-manual` (tipo `manual`), com `endpoint` definido para `ha-node-01`.
*   **Máquinas Juju:**
    *   `machine 0`: Corresponde a `ha-node-01`.
    *   `machine 1`: Corresponde a `ha-node-02` (adicionada via `juju add-machine ssh:...`).
    *   `machine 2` a `machine 7`: Contêineres LXC pré-provisionados (3 em `machine 0`, 3 em `machine 1`) para hospedar as unidades das aplicações.
*   **Deploy:** Cada charm (`postgresql`, `rabbitmq-server`, `landscape-server`, `haproxy`) é implantado individualmente, com suas unidades distribuídas entre as máquinas LXC (`--to lxd:X`).

### Resiliência e Alta Disponibilidade

*   **HA de Aplicação:** Múltiplas unidades de cada serviço são implantadas e distribuídas entre os dois nós físicos, garantindo que a falha de um contêiner ou de um nó físico não derrube o serviço.
*   **HA de Dados:** Charms como `postgresql` e `rabbitmq-server` formam clusters internos para replicação de dados.
*   **Mitigação de PoF de Infraestrutura:** A falha de um nó físico é mitigada pela distribuição das unidades e pela capacidade de recuperação do Juju, além de soluções de HA da plataforma de virtualização (VMware HA).

### Próximos Passos na Automação

O projeto está sendo refatorado para:
1.  Garantir a limpeza completa do ambiente antes de cada execução.
2.  Configurar o LXD de forma robusta em ambos os nós.
3.  Adicionar a nuvem manual e fazer o bootstrap do controlador.
4.  Adicionar o segundo nó físico ao modelo Juju.
5.  Pré-provisionar as máquinas contêiner LXC em ambos os nós físicos.
6.  Implantar cada charm individualmente, com posicionamento explícito nas máquinas LXC.
7.  Configurar as relações entre os charms.
8.  Escalar as unidades para HA (adicionando unidades aos contêineres no segundo nó físico).
9.  Verificar a saúde final do modelo.
