# Automação de Implantação do Canonical Landscape

Este projeto contém um conjunto de playbooks Ansible para automatizar a implantação do Canonical Landscape de forma robusta, flexível e resiliente, utilizando as melhores práticas de Infraestrutura como Código.

## Arquitetura e Funcionalidades Chave

Esta automação utiliza uma abordagem híbrida, combinando **Ansible** para orquestração e **Juju** para modelagem de aplicação, garantindo uma implantação estável e de fácil manutenção.

- **Automação Híbrida:** O Ansible gerencia a infraestrutura e o fluxo de trabalho, enquanto o Juju lida com o ciclo de vida complexo da aplicação Landscape, aproveitando o melhor de cada ferramenta.
- **Orquestração de Cluster Flexível:** Suporte para implantações de 1 a 2 nós, utilizando um playbook unificado para preparar qualquer VM para se tornar um host do cluster.
- **NFS Gerenciado pelo Juju:** O servidor NFS para os espelhos APT é implantado e gerenciado como um serviço dentro do cluster Juju, eliminando a necessidade de configuração manual nos hosts e simplificando a infraestrutura.
- **Gerenciamento Multi-Ambiente:** Suporte nativo para ambientes de **Teste** (nó único) e **Produção** (multi-nó, HA), controlados de forma declarativa pelos arquivos de inventário.
- **Deploy Atômico com Overlay:** A configuração de SSL é aplicada no momento do deploy via um _overlay_ dinâmico, uma estratégia avançada que elimina condições de corrida e garante que o cluster inicie em um estado consistente.
- **Ciclo de Vida Completo:** O `setup.sh` oferece macros para preparar nós, implantar, reconstruir e destruir ambientes de forma segura e previsível.
- **Auto-Recuperação (Self-Healing):** O playbook de verificação de saúde monitora ativamente o estado do cluster e, ao detectar uma unidade em erro, tenta recuperá-la automaticamente executando `juju resolve`.
- **UX Aprimorada (Feedback em Tempo Real):** Durante a longa espera do deploy, a automação exibe a saída do `juju status` em tempo real, permitindo que o operador acompanhe o progresso verdadeiro do cluster em vez de olhar para um spinner estático.
- **Tolerância a Ambientes Lentos:** O tempo de espera da automação foi estendido para 60 minutos, tornando-a robusta o suficiente para ser executada com sucesso mesmo em laboratórios ou VMs com recursos de CPU limitados.
- **Rede Simplificada (Multipass):** Inclui uma automação (`06-expose-proxy.yml`) que é executada automaticamente para expor a interface web do Landscape diretamente no IP da VM host, simplificando o acesso em ambientes de desenvolvimento.

## Como Usar

### Execução Robusta (Resiliência de Conexão)

Para proteger a execução de tarefas longas contra desconexões de rede, o script `setup.sh` possui uma verificação de cortesia. Ao ser iniciado, ele detecta se você está em uma sessão de terminal persistente (`tmux` ou `screen`).

- **Reconexão Automática:** Se uma sessão anterior chamada `landscape-automation` for encontrada, o script perguntará se você deseja se reconectar a ela, permitindo que você continue exatamente de onde parou.
- **Criação de Sessão:** Se nenhuma sessão for encontrada, ele irá alertá-lo e oferecer a criação de uma nova sessão `tmux` (preferencialmente) ou `screen` para continuar a execução com segurança.
- **Dashboard (com tmux):** Ao criar uma nova sessão com `tmux`, o script automaticamente divide a tela, mostrando o menu no painel superior e o `juju status --watch 1s` no painel inferior.
- **Instalação Automática:** Se nem `tmux` nem `screen` estiverem presentes, o script se oferecerá para instalar o `tmux` para você.

Recomenda-se a instalação do `tmux` (`sudo apt install tmux`) para a melhor experiência.

O único ponto de entrada para toda a automação é o script interativo `setup.sh`.

```bash
./setup.sh
```

### 1. Selecione o Ambiente

Você será solicitado a escolher entre **Teste** e **Produção**. A escolha do ambiente carrega as variáveis corretas do diretório `inventory/`.

### 2. Escolha a Ação

O menu principal oferece um controle completo sobre o ciclo de vida do cluster:

#### Ambiente de Teste

- **`1) Preparar Nós do Host`**: Executa o playbook para instalar todas as dependências e configurar as VMs que servirão como nós do cluster.
- **`2) Implantar Cluster (Primeira Vez)`**: Executa a sequência completa de playbooks para criar um novo cluster a partir do zero. Ideal para a primeira execução.
- **`3) Reconstruir Cluster (Ação Destrutiva)`**: A macro mais poderosa. Executa uma rotina de "terraplanagem" que destrói o ambiente Juju e o recria do zero. É a forma mais segura de garantir um ambiente 100% limpo.

#### Diagnóstico e Outras Opções (Todos os Ambientes)

- **`4) Exibir Status do Ambiente`**: Ferramenta de diagnóstico que executa `juju status` no modelo correto.
- **`5) Verificar Certificado do HAProxy`**: Exibe os detalhes de validade do certificado SSL em uso.
- **`6) Executar Health Check`**: Roda o playbook de verificação de saúde do cluster.
- **`7) Destruir Ambiente (IRREVERSÍVEL)`**: Remove completamente o ambiente Juju.
- **`8) Tarefas Avançadas (Manuais)`**: Submenu com ações granulares para administração.
- **`9) Sair`**: Encerra o script.

### Detalhes do Menu de Ações Manuais (Avançado)

O menu avançado oferece controle fino sobre configurações específicas do cluster:

- **`Aplicar Certificado PFX`**: Converte e aplica um certificado `landscape.pfx` localizado no diretório `cert/`. A senha do PFX deve estar configurada na variável `pfx_password` dentro do `vars/secrets.yml`.

- **`Verificar Certificado do HAProxy`**: Exibe os detalhes de validade (emissor, datas de início e expiração) do certificado SSL que está em uso pelo HAProxy, útil para diagnóstico rápido.

- **`Ativar Integração OIDC`**: Ativa o SSO lendo as configurações dos arquivos `vars/oidc_config.yml` (parâmetros públicos) e `vars/secrets.yml` (para o `oidc_client_secret`).

- **`Desativar Integração OIDC`**: Remove a configuração de SSO do Landscape, revertendo para a autenticação local de usuário e senha. Ideal para janelas de manutenção.

## Acessando os Contêineres para Manutenção

Cada aplicação do Landscape (haproxy, postgresql, etc.) roda em seu próprio contêiner LXD. Para depuração ou manutenção avançada, você pode acessar o shell de cada um.

### Passo 1: Identificar o Contêiner

A maneira mais fácil de mapear aplicações para contêineres é com o comando `juju status`.

```bash
sg lxd -c "juju status"
```

A saída mostrará a qual `Machine` cada unidade da aplicação pertence (ex: `haproxy/0` na `Machine 0`). O nome do contêiner LXD é o `hostname` dessa máquina (ex: `juju-a2fafe-0`).

Alternativamente, você pode listar todos os contêineres com `lxc list`.

### Passo 2: Acessar o Shell do Contêiner

Use o comando `lxc exec` para obter um shell bash dentro do contêiner desejado. Você terá privilégios de `root`.

```bash
# Formato: lxc exec <nome-do-container> -- bash
lxc exec juju-a2fafe-0 -- bash
```

### Passo 3: Comandos Úteis Dentro do Contêiner

Uma vez dentro, você pode usar comandos padrão do Linux para investigar:

- **Ver processos:** `ps aux`
- **Ver portas de rede:** `netstat -tulnp`
- **Acompanhar logs do sistema:** `journalctl -f`
- **Inspecionar arquivos de configuração (exemplo do HAProxy):** `cat /etc/haproxy/haproxy.cfg`

Este acesso direto é uma ferramenta poderosa para entender o que o Juju e os charms configuraram em cada componente do cluster.

## Segurança e CI/CD

O arquivo `vars/secrets.yml` é criptografado usando `ansible-vault` para proteger dados sensíveis. Para executar a automação em um pipeline de CI/CD (como o GitLab CI), é crucial manusear a senha do vault de forma segura.

- **NÃO** comite arquivos de senha (como `vault_pass.txt`) no repositório.
- **USE** as variáveis de ambiente secretas do seu sistema de CI/CD para armazenar a senha. O pipeline neste projeto (`.gitlab-ci.yml`) espera que a senha esteja em uma variável secreta chamada `ANSIBLE_VAULT_PASSWORD`.

Esta abordagem garante que os segredos não sejam expostos no código-fonte, alinhando-se com as melhores práticas de segurança.

## Histórico de Alterações

**05/10/2025:**

- **`Fixed`** Correção da falha de implantação do `haproxy` em ambiente de teste.
- O playbook `03-deploy-application.yml` foi ajustado para separar o deploy da configuração do `haproxy`, resolvendo o erro com o uso do parâmetro `--overlay`.
- Corrigido bug que aplicava o certificado SSL no lugar da chave privada.
- Para detalhes técnicos, consulte o [Diário de Bordo](diario-de-bordo.md).
