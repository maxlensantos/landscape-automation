# Manual de Uso do Pipeline de Testes CI/CD (Ansible & Juju)

Este documento serve como um guia para desenvolvedores e operadores que interagem com o pipeline de Integração Contínua (CI) do projeto `landscape-automation` no GitLab (git.serpro). O pipeline foi projetado para garantir a qualidade, a consistência e a confiabilidade da automação de implantação do Canonical Landscape.

## 1. Propósito do Pipeline de CI/CD

O principal objetivo deste pipeline é:
*   **Garantir a Qualidade do Código:** Verificar a sintaxe e o estilo dos playbooks Ansible, scripts shell e arquivos YAML.
*   **Validar a Funcionalidade:** Testar a idempotência e o comportamento esperado dos playbooks Ansible usando Molecule.
*   **Assegurar a Integração:** Realizar uma implantação completa do ambiente de teste para verificar a integração de todos os componentes Juju e Ansible.
*   **Detecção Precoce de Erros:** Identificar problemas de forma rápida e automática a cada alteração no código, reduzindo o tempo de depuração.
*   **Consistência da Implantação:** Garantir que a automação funcione de forma previsível em um ambiente limpo e isolado.

## 2. Componentes Chave

O pipeline utiliza as seguintes ferramentas e tecnologias:

*   **GitLab CI:** A plataforma de CI/CD que orquestra a execução dos testes.
*   **Ansible:** Ferramenta de automação para provisionamento de infraestrutura e configuração.
*   **Juju:** Orquestrador de serviços para modelagem e gerenciamento do ciclo de vida das aplicações.
*   **LXD:** Usado para criar máquinas virtuais leves (contêineres) onde o Juju bootstrapa seus controladores e modelos.
*   **Molecule:** Framework para testar playbooks e roles Ansible em ambientes efêmeros.
*   **Linters:** `ansible-lint`, `yamllint`, `shellcheck` para verificação de sintaxe e estilo.

## 3. Estágios do Pipeline

O pipeline é dividido nos seguintes estágios, executados sequencialmente:

### 3.1. `lint`

*   **Propósito:** Verificar a sintaxe, o estilo e as melhores práticas do código.
*   **Jobs:**
    *   `lint`: Executa `ansible-lint` (para playbooks Ansible), `yamllint` (para arquivos YAML) e `shellcheck` (para scripts Bash como `setup.sh`).
*   **Resultado:** Se qualquer linter encontrar erros, o job falhará, impedindo que o pipeline avance.

### 3.2. `molecule_test`

*   **Propósito:** Testar playbooks Ansible individualmente em ambientes efêmeros e isolados, garantindo sua idempotência e funcionalidade.
*   **Jobs:
    *   `molecule_prepare_vms`: Executa os testes do Molecule para o playbook `playbooks/00-prepare-vms.yml`. Este teste verifica se os pré-requisitos (Python, Snapd, Pip) são instalados corretamente.
    *   *(Serão adicionados mais jobs de Molecule para outros playbooks/roles conforme a necessidade.)*
*   **Como Funciona:** O Molecule provisiona um contêiner Docker (ou VM), executa o playbook (`converge.yml`), e depois executa um playbook de verificação (`verify.yml`) para checar o estado final do sistema.

### 3.3. `integration_test`

*   **Propósito:** Validar o fluxo completo de implantação do cluster Landscape, garantindo que todos os playbooks funcionem em conjunto e que o ambiente final esteja no estado desejado.
*   **Jobs:
    *   `full_integration_test`: Executa a sequência de playbooks Ansible (`00-prepare-vms.yml` a `06-expose-proxy.yml`) de forma não interativa, simulando uma implantação completa do ambiente de teste. Inclui a verificação de saúde (`98-verify-health.yml`) para confirmar que todas as aplicações Juju estão ativas e prontas.
*   **Resultado:** Se a implantação ou a verificação de saúde falhar, o job será marcado como falho.

### 3.4. `cleanup`

*   **Propósito:** Garantir que todos os recursos efêmeros criados durante os testes (controladores Juju, modelos, contêineres LXD) sejam removidos, mantendo o ambiente de CI limpo.
*   **Jobs:
    *   `cleanup_final`: Executa comandos para destruir controladores Juju, modelos e contêineres LXD.
*   **Execução:** Este estágio é configurado para sempre ser executado (`when: always`), mesmo que estágios anteriores falhem, para evitar recursos órfãos.

## 4. Como Acionar o Pipeline

O pipeline de CI/CD é acionado automaticamente nas seguintes situações:

*   **Push para qualquer branch:** A cada `git push`, o pipeline será executado para a branch em questão.
*   **Criação de Merge Request (MR):** Ao abrir ou atualizar um Merge Request, o pipeline será executado para a branch de origem do MR. Isso é crucial para validar as mudanças antes de serem mescladas na branch principal.

## 5. Interpretando os Resultados do Pipeline

Para visualizar o status e os logs do pipeline:

1.  **Navegue até o Projeto no GitLab:** Abra seu projeto `landscape-automation` no git.serpro.
2.  **Acesse CI/CD -> Pipelines:** Aqui você verá uma lista de todas as execuções de pipeline.
3.  **Status do Pipeline:
    *   **`passed` (verde):** Todas as etapas foram concluídas com sucesso.
    *   **`failed` (vermelho):** Uma ou mais etapas falharam.
    *   **`running` (azul/amarelo):** O pipeline está em execução.
    *   **`skipped` (cinza):** Algumas etapas foram puladas (ex: se uma regra `only/except` foi aplicada).
4.  **Detalhes do Job:** Clique no status de um pipeline para ver os jobs individuais. Clique em um job para ver seus logs detalhados. Os logs são essenciais para identificar a causa de uma falha.

## 6. Boas Práticas para Desenvolvedores

Para aproveitar ao máximo o pipeline de CI/CD e manter um fluxo de trabalho eficiente:

*   **Teste Localmente Primeiro:** Antes de fazer um `git push`, execute testes básicos localmente. Para Ansible, isso inclui:
    *   `ansible-lint playbooks/`
    *   `yamllint .`
    *   `shellcheck setup.sh`
    *   `molecule test -s playbooks/00-prepare-vms` (para testar playbooks específicos com Molecule).
*   **Commits Pequenos e Focados:** Faça commits que resolvam um único problema ou implementem uma única funcionalidade. Isso facilita a depuração se o pipeline falhar.
*   **Revise os Logs:** Se um pipeline falhar, sempre revise os logs do job falho. Eles fornecerão informações detalhadas sobre a causa do problema.
*   **Não Mescle Código Quebrado:** Nunca mescle um Merge Request se o pipeline de CI/CD estiver falhando.

## 7. Considerações de Segurança

*   **`ANSIBLE_VAULT_PASSWORD`:** A senha do Ansible Vault é uma informação sensível. Ela deve ser configurada como uma **variável secreta** no GitLab CI/CD (Configurações -> CI/CD -> Variáveis). **Nunca** a inclua diretamente no `.gitlab-ci.yml` ou no repositório.

## 8. Solução de Problemas Comuns

*   **"LXD/Juju não inicializa no runner":** Verifique se o runner está configurado para rodar em modo `privileged` e se tem acesso aos recursos necessários para virtualização.
*   **"Timeout no job de integração":** Implantações Juju podem levar tempo. Verifique os logs para identificar onde o processo está travando. Ajuste os timeouts do GitLab CI se necessário.
*   **"Erro de permissão":** Certifique-se de que o usuário `gitlab-runner` (ou o usuário configurado no seu runner) tenha as permissões corretas para interagir com LXD e Juju (ex: membro do grupo `lxd`).

Este manual será atualizado conforme o pipeline evolui e novas funcionalidades de teste são adicionadas.
