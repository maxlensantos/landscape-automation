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

*   **Ansible (O Orquestrador):** É responsável pela camada de infraestrutura e preparação do ambiente. Suas tarefas incluem:
    *   Instalar pacotes e dependências (LXD, Juju client).
    *   Configurar o ambiente base (redes, usuários).
    *   Orquestrar o fluxo de execução através de playbooks sequenciais.
    *   Gerenciar tarefas externas ao ciclo de vida da aplicação (ex: certificados, redirecionamento de portas).

*   **Juju (O Modelador de Aplicação):** É responsável pelo ciclo de vida da aplicação Landscape.
    *   **Por quê?** O Landscape é uma aplicação complexa e com estado, com múltiplas partes que se relacionam (servidor, banco de dados, mensageria). Juju é a ferramenta da Canonical desenhada especificamente para modelar e gerenciar essas relações complexas de forma robusta.
    *   A topologia da aplicação é definida e implantada usando o **bundle oficial `landscape-scalable`** do canal `stable`. A configuração específica do ambiente (como certificados SSL) é aplicada atomicamente no momento do deploy através de um arquivo de **overlay**.

## 3. Gerenciamento de Ambientes (Teste vs. Produção)

A automação foi desenhada para ser flexível e suportar múltiplos ambientes de forma limpa.

*   **Fonte da Verdade:** Os arquivos de inventário em `inventory/` (`testing.ini`, `production.ini`).
*   **Mecanismo de Controle:** A variável `is_ha_cluster: <true|false>` no inventário é a chave que direciona toda a lógica condicional nos playbooks.
*   **Topologia Declarativa:** A diferença entre os ambientes é gerenciada pelo `overlay-ha.yaml`, que modifica o `bundle-base.yaml` apenas com as diferenças para produção. Esta é uma premissa de design importante para evitar duplicação de código.

## 4. Estrutura e Convenções do Projeto

*   `setup.sh`: É o **ponto de entrada único e seguro** para os operadores. A premissa é que os playbooks nunca devem ser executados manualmente.
*   `playbooks/`: Organizados em uma sequência numérica que representa a ordem lógica de execução.
*   `vars/`: `main.yml` para variáveis comuns e `secrets.yml` para dados sensíveis, sempre criptografado com `ansible-vault`.
*   **Idempotência:** Todas as tarefas devem ser, sempre que possível, idempotentes. Elas devem poder ser executadas múltiplas vezes sem causar efeitos colaterais indesejados.
*   **Acesso em Ambientes Virtualizados (Multipass):** Para ambientes de desenvolvimento em VMs, a automação deve garantir o redirecionamento de portas (ex: 80, 443) da VM para o contêiner do proxy reverso (HAProxy) para permitir o acesso externo à interface. Esta lógica deve ser parte do fluxo de implantação padrão.

## 5. Como Manter e Evoluir o Projeto

Para garantir a consistência e a qualidade, qualquer desenvolvedor (humano ou IA) deve seguir estas premissas:

1.  **Leia este documento (`ARCHITECTURE.md`) primeiro.**
2.  **Valide as mudanças:** Sempre execute a macro `RECONSTRUIR Ambiente de Teste Completo` para garantir que sua mudança não quebrou o ciclo de vida completo da automação.
3.  **Documente as mudanças:** Após a implementação, atualize o `diario-de-bordo.md` e, se necessário, o `README.md`.

## 6. Diretrizes para Assistentes de IA

Qualquer assistente de IA que interaja com este codebase deve aderir estritamente às seguintes diretrizes para garantir consistência e qualidade:

1.  **Fonte da Verdade:** Este documento (`ARCHITECTURE.md`) é sua fonte primária de informação. Leia-o antes de qualquer outra ação. As premissas aqui descritas não são negociáveis.

2.  **Ponto de Entrada:** O script `setup.sh` é o único ponto de entrada para operadores. **Nunca** instrua o usuário a executar playbooks `ansible-playbook` diretamente. Suas modificações devem aprimorar o `setup.sh` ou os playbooks que ele chama, mantendo-o como a interface principal.

3.  **Respeite o Modelo Híbrido:** Entenda a separação de responsabilidades entre Ansible (infraestrutura) e Juju (aplicação). Não tente gerenciar o ciclo de vida da aplicação com Ansible, nem a preparação da infraestrutura com Juju.

4.  **Idempotência é Lei:** Todas as alterações em playbooks devem ser idempotentes. O sistema deve poder ser executado várias vezes, chegando sempre ao mesmo estado desejado.

5.  **Validação Obrigatória:** Após qualquer modificação, descreva como você validaria a mudança. O método preferencial é através da macro `RECONSTRUIR Ambiente de Teste Completo` disponível no `setup.sh`.