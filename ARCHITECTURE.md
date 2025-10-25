# Arquitetura e Premissas do Projeto "landscape-automation"

<!--
NOTA PARA ASSISTENTES DE IA:
Este documento é a fonte da verdade sobre a arquitetura e as decisões de design deste projeto.
Leia e compreenda este arquivo antes de propor ou realizar qualquer alteração no código.
-->

## 1. Visão Geral e Objetivo

O objetivo deste projeto é automatizar a implantação do Canonical Landscape, oferecendo um método seguro e repetível para criar ambientes de teste (nó único) e de produção (multi-nó, HA).

## 2. Arquitetura Principal: O Modelo Híbrido

A premissa fundamental deste projeto é a utilização de um **modelo híbrido**, combinando Ansible e Juju para tirar proveito da força de cada ferramenta.

- **Ansible (O Orquestrador):** É responsável pela camada de infraestrutura e preparação do ambiente. Suas tarefas incluem:
  - Instalar pacotes e dependências (LXD, Juju client).
  - Configurar o ambiente base (redes, usuários, túneis VXLAN).
  - Orquestrar o fluxo de execução através de playbooks sequenciais.
  - Gerenciar tarefas externas ao ciclo de vida da aplicação (ex: certificados, redirecionamento de portas).

- **Juju (O Modelador de Aplicação e Serviços):** É responsável pelo ciclo de vida da aplicação Landscape e de seus serviços de suporte.
  - **Por quê?** O Landscape é uma aplicação complexa e com estado. Juju é a ferramenta da Canonical desenhada para modelar e gerenciar essas relações de forma robusta.
  - Nesta arquitetura, o Juju gerencia não apenas a pilha do Landscape (servidor, banco de dados, etc.), mas também serviços de infraestrutura essenciais para o cluster, como o **servidor NFS** para o espelho de pacotes APT. Isso centraliza o gerenciamento de estado no Juju.
  - A topologia da aplicação é definida e implantada usando o **bundle oficial `landscape-scalable`**, com serviços adicionais (como o NFS) sendo orquestrados e relacionados via playbooks Ansible.

## 2.1. Visão de Infraestrutura e Topologia de Rede (vSphere)

Esta seção detalha a arquitetura de rede projetada para um ambiente VMware vSphere, garantindo alta disponibilidade e performance.

### Princípio Fundamental: vNIC Única

- **Interface Única:** Cada VM (`lansrv01`, `lansrv02`) possui apenas **uma única interface de rede virtual (vNIC)**.
- **Consolidação de Tráfego:** Esta vNIC é conectada à **"Rede Microsegmentação BSA"** e é responsável por transportar todo o tráfego, incluindo:
  1.  **Tráfego de Gerenciamento:** Conexão do Ansible, comunicação do controlador Juju com seus agentes.
  2.  **Tráfego da Aplicação:** Acesso dos usuários finais ao HAProxy.
  3.  **Tráfego de Underlay:** Os pacotes UDP encapsulados da rede overlay VXLAN viajam entre as VMs através desta rede.

### Topologia de Rede Lógica

Existem duas redes lógicas principais operando em conjunto:

#### 1. Rede Microsegmentação BSA (Underlay Físico/Virtual)
- Esta é a rede à qual as vNICs das VMs estão conectadas.
- **Requisito:** Deve haver conectividade IP completa (Camada 3) entre todas as VMs nesta rede.
- **Consideração:** A vNIC única precisa ter largura de banda adequada para suportar a soma de todos os tipos de tráfego.

#### 2. LXD Overlay Network (Overlay Lógico)
- **Tecnologia:** Esta rede é criada e gerenciada pelo LXD/Juju usando **VXLAN**.
- **Função:** Conecta de forma transparente todos os contêineres LXD (`landscape-server`, `rabbitmq-server`, `haproxy`, `nfs-server`), independentemente de em qual VM (`lansrv01` ou `lansrv02`) eles estejam rodando.
- **Funcionamento:** O tráfego dos contêineres é encapsulado em pacotes UDP pelo VXLAN. O switch virtual do VMware vê apenas pacotes UDP sendo trocados entre os IPs das VMs, não o tráfego interno dos contêineres.

### Requisitos do VMware vSphere

Para que esta arquitetura funcione corretamente, a infraestrutura vSphere deve garantir o seguinte:

- **Regra de Anti-Afinidade (DRS):** Uma regra **obrigatória** deve ser criada para garantir que as VMs `lansrv01` e `lansrv02` sempre residam em hosts ESXi físicos distintos. Isso garante a alta disponibilidade em caso de falha de um host físico.
- **Virtualização de Hardware:** As extensões de virtualização de hardware (Intel VT-x / AMD-V) devem ser expostas para as VMs para permitir a execução dos contêineres LXD.
- **Ponto Crítico de Rede:** Devido ao uso de uma rede overlay VXLAN, **NÃO é necessário habilitar "Modo Promíscuo" ou aceitar "Transmissões Falsificadas" (Forged Transmits)** no Port Group do vSwitch. O encapsulamento do VXLAN torna essas configurações desnecessárias.

### Fluxos de Comunicação

- **Juju:** O controlador Juju (no SO base do `lansrv01`) se comunica com os agentes Juju (no SO base de ambas as VMs) através da "Rede Microsegmentação BSA".
- **Aplicação:** Os serviços dentro dos contêineres (ex: `landscape-server` falando com `postgresql`) se comunicam diretamente através da "LXD Overlay Network" (`172.16.0.0/24`), de forma transparente e segura.

## 3. Gerenciamento de Ambientes (Teste vs. Produção)

A automação foi desenhada para ser flexível e suportar múltiplos ambientes de forma limpa.

- **Fonte da Verdade:** Os arquivos de inventário em `inventory/` (`testing.ini`, `production.ini`). Eles definem as variáveis do ambiente e os hosts que comporão o cluster.
- **Grupo de Hosts:** Os nós que formarão o cluster Juju/LXD devem ser listados no grupo `[lxd_hosts]` do inventário.
- **Mecanismo de Controle:** A variável `is_ha_cluster: <true|false>` no inventário continua sendo a chave que direciona a lógica condicional.
- **Topologia Declarativa:** A diferença entre os ambientes é gerenciada pelo `overlay-ha.yaml`, que modifica o `bundle-base.yaml` apenas com as diferenças para produção. Esta é uma premissa de design importante para evitar duplicação de código.

## 4. Estrutura e Convenções do Projeto

- `setup.sh`: É o **ponto de entrada único e seguro** para os operadores. A premissa é que os playbooks nunca devem ser executados manualmente.
- `playbooks/`: Organizados em uma sequência numérica que representa a ordem lógica de execução.
  - `00-prepare-host-nodes.yml`: Prepara as VMs que servirão como nós do cluster (instala LXD, Juju, configura redes, etc.).
  - `02-bootstrap-juju.yml`: Inicia o controlador Juju e adiciona os nós preparados como máquinas Juju.
  - `03-deploy-application.yml`: Implanta o bundle do Landscape.
  - `00-deploy-nfs-server.yml`: Implanta e configura o charm do NFS para o espelho APT.
  - Playbooks subsequentes (`98-verify-health.yml`, etc.) cuidam da verificação e exposição do serviço.
- `vars/`: `main.yml` para variáveis comuns e `secrets.yml` para dados sensíveis, sempre criptografado com `ansible-vault`.
- **Idempotência:** Todas as tarefas devem ser, sempre que possível, idempotentes. Elas devem poder ser executadas múltiplas vezes sem causar efeitos colaterais indesejados.
- **Acesso em Ambientes Virtualizados (Multipass):** Para ambientes de desenvolvimento em VMs, a automação deve garantir o redirecionamento de portas (ex: 80, 443) da VM para o contêiner do proxy reverso (HAProxy) para permitir o acesso externo à interface. Esta lógica deve ser parte do fluxo de implantação padrão.

## 5. Como Manter e Evoluir o Projeto

Para garantir a consistência e a qualidade, qualquer desenvolvedor (humano ou IA) deve seguir estas premissas:

1.  **Leia este documento (`ARCHITECTURE.md`) primeiro.**
2.  **Valide as mudanças:** Sempre execute a macro `RECONSTRUIR Ambiente de Teste Completo` para garantir que sua mudança não quebrou o ciclo de vida completo da automação.
3.  **Documente as mudanças:** Após a implementação, atualize o `diario-de-bordo.md` e, se necessário, o `README.md`.

## 5.1. Premissas de Compatibilidade

- **Versão do Charm vs. Base do SO:** A versão de um charm do Juju, definida pelo seu canal (ex: `14/stable`), está diretamente atrelada à versão da base do sistema operacional (ex: `ubuntu@22.04`) em que ele pode ser implantado.
- **Exemplo Crítico:** O charm `postgresql` no canal `14/stable` é compatível apenas com a base Ubuntu 22.04. Para uma base `Ubuntu 24.04`, é **mandatório** usar um canal compatível, como o `16/stable`.
- **Diretriz:** Antes de definir um canal de charm nos playbooks, sempre verifique a compatibilidade com a base do SO de destino na página do charm no Charmhub.

## 6. Diretrizes para Assistentes de IA

Qualquer assistente de IA que interaja com este codebase deve aderir estritamente às seguintes diretrizes para garantir consistência e qualidade:

1.  **Fonte da Verdade:** Este documento (`ARCHITECTURE.md`) é sua fonte primária de informação. Leia-o antes de qualquer outra ação. As premissas aqui descritas não são negociáveis.

2.  **Ponto de Entrada:** O script `setup.sh` é o único ponto de entrada para operadores. **Nunca** instrua o usuário a executar playbooks `ansible-playbook` diretamente. Suas modificações devem aprimorar o `setup.sh` ou os playbooks que ele chama, mantendo-o como a interface principal.

3.  **Respeite o Modelo Híbrido:** Entenda a separação de responsabilidades entre Ansible (infraestrutura) e Juju (aplicação). Não tente gerenciar o ciclo de vida da aplicação com Ansible, nem a preparação da infraestrutura com Juju.

4.  **Idempotência é Lei:** Todas as alterações em playbooks devem ser idempotentes. O sistema deve poder ser executado várias vezes, chegando sempre ao mesmo estado desejado.

5.  **Validação Obrigatória:** Após qualquer modificação, descreva como você validaria a mudança. O método preferencial é através da macro `RECONSTRUIR Ambiente de Teste Completo` disponível no `setup.sh`.
