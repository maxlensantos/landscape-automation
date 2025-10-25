# **Análise Exaustiva e Resolução do Erro de Hook reverseproxy-relation-changed em Implantações Juju do Landscape Escalável**

## **Sumário Executivo**

Este relatório técnico fornece uma análise aprofundada e uma metodologia de resolução para o erro crítico hook failed: "reverseproxy-relation-changed", encontrado durante a implantação de uma arquitetura escalável do Canonical Landscape utilizando o orquestrador de serviços Juju. Este erro representa uma falha fundamental no ciclo de vida da relação Juju, ocorrendo no momento preciso em que o charm do HAProxy tenta configurar-se dinamicamente como um proxy reverso para o serviço landscape-server. A falha deste hook impede a conclusão da implantação, deixando a pilha de serviços em um estado não funcional.

A análise identifica três categorias principais de causas raiz:

1. **Discrepâncias de Configuração:** A causa mais provável, com ênfase particular em configurações de certificados SSL/TLS ausentes, malformadas ou propagadas incorretamente através da relação.
2. **Violações de Integridade de Dados da Relação:** Falhas decorrentes do envio de dados pela aplicação landscape-server em um formato ou estrutura que o script do hook do HAProxy não espera, levando a erros de tempo de execução.
3. **Inconsistências Ambientais:** Diferenças sutis, mas impactantes, no estado do modelo Juju, dependendo do método de implantação utilizado (linha de comando versus interface gráfica), que podem introduzir condições de corrida (_race conditions_) ou aplicar configurações padrão problemáticas.

Para abordar este desafio de forma sistemática, o relatório está estruturado para guiar o operador desde os conceitos fundamentais da arquitetura até um fluxo de trabalho de diagnóstico prático e hands-on. Inicialmente, detalha-se a arquitetura do bundle landscape-scalable e os mecanismos de relação do Juju. Em seguida, realiza-se uma análise profunda da lógica interna do hook reverseproxy-relation-changed e do "contrato" de dados que ele estabelece com as aplicações relacionadas. Com base nesta fundação, o relatório apresenta um fluxo de trabalho de troubleshooting em quatro fases, utilizando ferramentas avançadas do Juju como juju debug-log e juju debug-hooks para isolar a causa raiz com precisão cirúrgica. Finalmente, são fornecidas recomendações estratégicas e melhores práticas para a criação de implantações declarativas, robustas e reproduzíveis, visando prevenir a recorrência deste e de outros erros de integração complexos.

## **Seção 1: A Arquitetura landscape-scalable e as Relações Juju**

Para diagnosticar eficazmente a falha de um hook de relação, é imperativo primeiro compreender a arquitetura do sistema que está sendo implantado e os princípios de orquestração que governam suas interações. O erro não ocorre no vácuo, mas sim no contexto de um modelo de serviço complexo gerenciado pelo Juju.

### **1.1. Blueprint Arquitetural de uma Implantação de Alta Disponibilidade do Landscape**

A implantação de uma infraestrutura escalável do Canonical Landscape com Juju é realizada através de "bundles", que são arquivos YAML que descrevem um conjunto de aplicações, suas configurações e, crucialmente, as relações entre elas.1

#### **1.1.1. Desconstruindo o Bundle landscape-scalable**

O bundle landscape-scalable é a única configuração oficialmente suportada pela Canonical para novas implantações de alta disponibilidade (HA) do Landscape.1 Ele foi projetado para orquestrar quatro charms de máquina principais, com cada aplicação destinada a ser implantada em sua própria máquina virtual ou física para garantir isolamento e escalabilidade.3 Os componentes são:

- **haproxy:** Atua como o ponto de entrada da rede, funcionando como um balanceador de carga e proxy reverso. É responsável pela terminação SSL/TLS, distribuindo o tráfego de entrada para as várias unidades do landscape-server.5 A falha do hook ocorre nesta aplicação.
- **landscape-server:** É o coração da aplicação, fornecendo a interface web e a lógica de negócios para o gerenciamento de sistemas Ubuntu.4
- **postgresql:** Serve como o banco de dados relacional para persistir todos os dados do Landscape, desde informações de máquinas registradas até históricos de pacotes e atividades.3
- **rabbitmq-server:** Funciona como um message broker, gerenciando a comunicação assíncrona entre os clientes Landscape (agentes nas máquinas gerenciadas) e o landscape-server.3

O processo de implantação padrão, conforme a documentação oficial, segue uma sequência clara:

1. Criação de um modelo Juju: juju add-model landscape-self-hosted.3
2. Implantação do bundle: juju deploy landscape-scalable.3 Este comando provisiona uma unidade de cada um dos quatro serviços.
3. Escalabilidade para HA: Para alcançar uma configuração de três nós, adicionam-se duas unidades a cada aplicação: juju add-unit landscape-server \-n 2, juju add-unit haproxy \-n 2, e assim por diante.3

#### **1.1.2. A Depreciação de Bundles Antigos**

É fundamental notar que bundles mais antigos, como landscape-dense e landscape-dense-maas, estão agora depreciados e não são mais suportados.1 Relatos de erro, como o que motivou esta análise, foram frequentemente observados com esses bundles mais antigos, que tentavam colocalizar vários serviços em uma única máquina usando contêineres LXD.7 Embora a arquitetura de implantação seja diferente, o charm

haproxy subjacente e sua lógica de relação reverseproxy são em grande parte os mesmos. Portanto, os problemas identificados nesses cenários legados permanecem altamente relevantes para a depuração de falhas no bundle landscape-scalable moderno.

### **1.2. O Modelo de Relação do Juju: Integração Automatizada como Código**

O Juju transcende as ferramentas de implantação tradicionais ao modelar as _relações_ entre os serviços como um primitivo de primeira classe.2 Em vez de configurar manualmente os pontos de conexão, o Juju automatiza esse processo através de um "contrato" bem definido entre os charms.

- **Endpoints e Interfaces:** Cada charm declara em seu arquivo metadata.yaml os "endpoints" que expõe. Um endpoint tem um nome (ex: db, website, reverseproxy) e uma "interface", que define o protocolo ou o conjunto de dados que ele espera trocar.9 No nosso caso, o  
  landscape-server oferece um endpoint website que implementa a interface http, e o haproxy requer um endpoint reverseproxy que também utiliza a interface http.9 A compatibilidade de interface é o que permite que a relação seja estabelecida.
- **Relation Databags:** Quando o comando juju integrate landscape-server haproxy é executado (ou quando a relação é definida no bundle.yaml), o controlador Juju estabelece um canal de comunicação entre as duas aplicações. Este canal é implementado como um conjunto de armazenamentos de chave-valor chamados "databags".12 É através desses databags que o  
  landscape-server publica suas informações de conexão (como endereço IP e porta), e o haproxy as lê para se autoconfigurar.
- **Hooks: O Motor da Automação:** Os hooks são scripts executáveis (geralmente em Bash ou Python) localizados no diretório hooks/ de um charm.13 O agente Juju em uma unidade executa esses scripts em resposta a eventos específicos no ciclo de vida do modelo. Por exemplo:
  - install: Executado uma vez quando o charm é implantado pela primeira vez na unidade.
  - config-changed: Executado quando a configuração do charm é alterada via juju config.
  - \<relação\>-relation-changed: Executado sempre que os dados no databag de uma relação são alterados por uma unidade remota.

O erro hook failed: "reverseproxy-relation-changed" indica que o script hooks/reverseproxy-relation-changed dentro do charm haproxy foi executado pelo agente Juju, mas terminou com um código de saída diferente de zero, sinalizando uma falha catastrófica em seu processo de execução. A falha não é apenas um bug em um script isolado; é um colapso na comunicação e automação modelada entre o landscape-server e o haproxy. A integridade de toda a implantação depende da execução bem-sucedida deste contrato de integração.

## **Seção 2: Uma Análise Profunda da Interface reverseproxy do Charm HAProxy**

O epicentro da falha reside na interação entre o landscape-server e o haproxy através da relação reverseproxy. Para entender por que o hook falha, devemos dissecar o "contrato" desta relação: o que o charm HAProxy espera receber, como ele processa essa informação e quais são seus pontos de fragilidade.

### **2.1. Anatomia do Charm HAProxy**

O charm do HAProxy é um exemplo de um operador Juju poderoso e flexível. Sua complexidade e poder derivam em grande parte de como ele lida com a configuração.

#### **2.1.1. A Configuração services**

Diferente de charms com dezenas de opções de configuração granulares, grande parte do comportamento do HAProxy é controlada por uma única e complexa opção de configuração chamada services.15 Esta opção aceita uma string formatada em YAML que define de forma declarativa as seções

frontend e backend do arquivo de configuração final do HAProxy (haproxy.cfg).

O charm possui uma lógica interna sofisticada que analisa este YAML. Ele é capaz de identificar quais diretivas pertencem a um frontend (como acl ou use_backend) e quais pertencem a um backend (como balance ou reqirep), e as renderiza nos locais apropriados do arquivo de configuração. Isso permite uma personalização extremamente detalhada do comportamento do proxy reverso diretamente através da configuração do Juju.15

#### **2.1.2. Fusão de Dados da Relação**

O mecanismo mais crítico para o nosso problema é como o charm lida com as relações reverseproxy. Quando uma aplicação, como landscape-server, é relacionada ao HAProxy através deste endpoint, um processo de configuração automática é iniciado 15:

1. **Criação Automática de Backend:** O charm haproxy utiliza o nome da aplicação Juju relacionada (neste caso, landscape-server) como o service_name para uma nova seção de backend no haproxy.cfg.
2. **Fusão de Configurações:** A lógica do charm então procura por uma entrada correspondente (service_name: landscape-server) na configuração services do próprio charm. Se encontrada, as opções definidas ali são usadas como base para a configuração do backend.
3. **Incorporação de Dados da Relação:** Os dados fornecidos pela aplicação landscape-server através do databag da relação (como os endereços IP e portas de suas unidades) são usados para gerar as linhas server \<nome\> \<ip\>:\<porta\>... dentro desta seção de backend.

Este processo de fusão é onde a automação acontece, mas também é uma fonte potencial de erros. Se os dados da relação estiverem ausentes, malformados ou entrarem em conflito com a configuração estática, o processo de renderização do haproxy.cfg pode falhar.

### **2.2. O Protocolo reverseproxy: O Contrato de Dados**

A relação reverseproxy funciona com base em um protocolo implícito, um "contrato" de dados entre a aplicação que "provê" o serviço web e o charm haproxy que o "requer".

- **Obrigação do Provedor (landscape-server):** A aplicação que se conecta ao reverseproxy (neste caso, landscape-server através de seu endpoint website) tem a obrigação de publicar informações essenciais no databag da relação para cada uma de suas unidades. No mínimo, o charm haproxy espera encontrar as chaves hostname (o endereço IP privado da unidade) e port (a porta na qual o serviço web está escutando).17
- **Expectativa do Requerente (haproxy):** O script do hook reverseproxy-relation-changed no charm haproxy é acionado sempre que esses dados são adicionados ou alterados. O script executa o comando relation-get para ler os valores de hostname e port de cada unidade remota e os utiliza para construir a configuração do backend.10
- **Uma Armadilha Comum: A Fragilidade do Contrato:** Uma causa documentada de falha deste hook é a violação do formato de dados esperado. Em uma discussão, um desenvolvedor de um charm customizado encontrou este erro exato porque seu charm estava passando os dados de serviço como um dicionário Python (dict), enquanto a lógica de parsing do hook haproxy esperava incondicionalmente uma lista (list) de dicionários.20 Isso resultou em um  
  TypeError dentro do script do hook, causando sua falha imediata.

Este exemplo revela uma característica fundamental do problema: a relação reverseproxy opera com base em um esquema de dados implícito e não rigorosamente validado. O script do hook foi escrito com fortes suposições sobre a estrutura e os tipos de dados que receberia. A ausência de uma validação de esquema robusta torna o hook "frágil" e suscetível a falhas se um charm relacionado se desviar, mesmo que ligeiramente, do formato esperado. A implicação direta é que o charm landscape-server, sob certas condições (como versões específicas, caminhos de implantação ou bugs transitórios), pode estar enviando dados que violam este contrato implícito, fazendo com que o hook "frágil" do haproxy quebre.

## **Seção 3: Análise da Causa Raiz da Falha do Hook**

Com uma compreensão da arquitetura e da mecânica da relação, podemos agora sintetizar as informações para analisar as causas raiz mais prováveis para a falha do hook reverseproxy-relation-changed.

### **3.1. Dissecando a Lógica do Hook reverseproxy-relation-changed**

A função principal deste script é orquestrar a reconfiguração do serviço HAProxy em resposta a mudanças nas aplicações de backend. O fluxo lógico geral é o seguinte:

1. **Coleta de Dados:** O script itera sobre todas as relações reverseproxy ativas. Para cada relação, ele usa relation-get para coletar os dados de configuração (IP, porta, etc.) de cada unidade remota.
2. **Fusão de Configuração:** Ele combina esses dados dinâmicos da relação com a configuração estática definida na opção services do charm.
3. **Manuseio de Certificados:** Uma parte crucial do script lida com certificados SSL/TLS. Ele verifica se há dados de certificado e chave privada na configuração ou na relação, decodifica-os (geralmente de base64) e os escreve em arquivos no sistema de arquivos da unidade (por exemplo, /var/lib/haproxy/service\_.../0.pem) para que o HAProxy possa usá-los.21
4. **Renderização de Template:** Usando todos os dados coletados e processados, o script renderiza um novo arquivo haproxy.cfg a partir de um template.
5. **Validação e Recarga:** Antes de aplicar a nova configuração, ele executa um comando de validação (haproxy \-c). Se a validação for bem-sucedida, ele recarrega o serviço HAProxy para aplicar as mudanças.

A falha pode ocorrer em qualquer um desses estágios. Um erro de parsing nos dados da relação (Ponto 2), um problema ao escrever um arquivo de certificado (Ponto 3), ou uma configuração final sintaticamente inválida (Ponto 4\) fará com que o script termine com um erro, resultando no estado hook failed.

### **3.2. Cenário de Falha 1: Erros de Configuração SSL/TLS (Alta Probabilidade)**

A evidência aponta fortemente para problemas relacionados a SSL/TLS como uma das principais causas.

- **Evidências:**
  - Em uma discussão sobre o erro, um usuário experiente sugeriu imediatamente verificar a "configuração ausente para o certificado ssl".7
  - Um relatório de bug detalha um cenário em que o landscape-client não consegue se conectar ao servidor devido a erros de validação de certificado, indicando que o certificado correto não foi propagado do HAProxy para os outros componentes do sistema.22
  - Outro relatório de bug mostra um traceback do hook reverseproxy-relation-changed falhando especificamente porque um arquivo de certificado (0.pem) não pôde ser criado, implicando que os dados do certificado estavam ausentes ou malformados.21
- **Mecanismo da Falha:** O bundle landscape-scalable é projetado para operar sobre HTTPS, o que significa que a terminação SSL no HAProxy é um requisito. O charm haproxy espera receber os dados do certificado e da chave privada. Isso pode ser feito de várias maneiras: através das opções de configuração do próprio charm (ssl_cert, ssl_key), ou através de uma relação com um charm provedor de certificados, como self-signed-certificates ou letsencrypt-lego-operator.6 Se esses dados não forem fornecidos corretamente no momento em que o hook  
  reverseproxy-relation-changed é executado, a etapa de "Manuseio de Certificados" falhará. O script tentará acessar dados que não existem ou escrever um arquivo vazio, resultando em um erro de I/O ou um traceback de Python, que por sua vez causa a falha do hook.

### **3.3. Cenário de Falha 2: Violações de Integridade e Esquema de Dados da Relação**

Conforme estabelecido na Seção 2, a lógica de parsing do hook é frágil e sensível ao formato dos dados recebidos.

- **Evidências:** O caso mais claro é o exemplo de um charm enviando um dicionário (dict) quando uma lista (list) era esperada, causando um TypeError.20 Isso representa uma violação direta do esquema de dados implícito da relação.
- **Mecanismo da Falha:** O código Python do hook provavelmente contém um laço de repetição como for service_config in services_data:. Se a variável services_data, preenchida com dados da relação, for um dicionário em vez de uma lista, a tentativa de iterar sobre ela levantará uma exceção TypeError, interrompendo abruptamente a execução do script e colocando a unidade em estado de erro.

### **3.4. Cenário de Falha 3: Discrepâncias Ambientais e do Método de Implantação**

A evidência mais intrigante vem de um relato de usuário que observou uma diferença consistente no resultado com base no método de implantação.

- **Evidências:** Um usuário relatou repetidamente que a implantação do bundle landscape-dense-maas via um comando CLI simples (juju deploy landscape-dense-maas) funcionava perfeitamente. No entanto, ao usar a Juju GUI ou um comando CLI que fixava uma revisão de bundle específica e mais antiga (juju deploy cs:bundle/landscape-dense-maas-7), o erro no HAProxy ocorria de forma consistente.7 Esta observação persistiu ao longo de anos e com diferentes versões do Ubuntu.
- **Mecanismo da Falha (Hipótese de Condição de Corrida):** A natureza assíncrona do Juju, combinada com as diferenças operacionais entre a CLI e a GUI, pode criar uma condição de corrida (_race condition_).
  1. Uma implantação do landscape-scalable inicia a criação de múltiplas aplicações e relações simultaneamente.3
  2. O landscape-server precisa informar ao haproxy como se conectar a ele. Em alguns cenários, ele também pode solicitar ao haproxy que use um certificado SSL padrão, como visto em uma mensagem de log: "No SSL configuration keys found, asking HAproxy to use the 'DEFAULT' certificate".22
  3. **A Corrida:** O hook reverseproxy-relation-changed no haproxy é acionado. Ele recebe a solicitação do landscape-server para usar o certificado 'DEFAULT'. No entanto, se a configuração do próprio haproxy que define este certificado 'DEFAULT' (por exemplo, através de juju config haproxy ssl_cert=...) ainda não foi processada pelo agente Juju do haproxy, o hook falhará ao tentar acessar um recurso que ainda não existe.21
  4. Uma implantação via CLI a partir de um bundle.yaml tende a ser mais atômica. O Juju pode processar todas as configurações definidas no bundle em uma transação inicial, garantindo que o haproxy tenha sua configuração de certificado _antes_ que qualquer hook de relação seja acionado.
  5. Por outro lado, uma implantação via GUI é mais interativa e sequencial. Um operador pode primeiro arrastar e soltar os charms, o que estabelece a relação, e _depois_ preencher os formulários de configuração. Essa sequência de eventos cria a janela de oportunidade perfeita para a condição de corrida: a relação é estabelecida e o hook é acionado antes que a configuração necessária esteja no lugar, levando à falha.

## **Seção 4: Um Fluxo de Trabalho Sistemático de Troubleshooting e Resolução**

Esta seção apresenta um guia prático e metódico para diagnosticar e resolver o erro hook failed no seu ambiente. O processo é dividido em quatro fases, progredindo da coleta de informações de alto nível para a depuração interativa e a intervenção direta.

### **4.1. Fase 1: Triagem Inicial e Análise de Logs**

O primeiro passo em qualquer depuração é coletar o máximo de contexto possível usando as ferramentas padrão do Juju.

#### **4.1.1. Coletando Contexto com juju status**

Execute o comando juju status \--relations. Esta é a visão mais completa do estado do seu modelo.17 Analise a saída para confirmar:

- A unidade haproxy está em estado de error.
- A mensagem de status da unidade haproxy corresponde a hook failed: reverseproxy-relation-changed.
- Na seção Relations, verifique se a relação entre haproxy:reverseproxy e landscape-server:website está estabelecida.

#### **4.1.2. Mergulho Profundo nos Logs com juju debug-log**

O comando juju debug-log é a ferramenta mais crítica para a análise inicial, pois transmite os logs de todos os agentes Juju no modelo.25 Para evitar ser sobrecarregado com informações, use filtros para isolar a falha:

Bash

juju debug-log \--replay \--level=ERROR \--include=haproxy/0

- \--replay: Mostra todo o histórico de logs, não apenas as novas mensagens.
- \--level=ERROR: Filtra para mostrar apenas mensagens de nível ERROR e CRITICAL.
- \--include=haproxy/0: Mostra apenas logs originados da unidade haproxy/0 (ajuste o número da unidade se necessário).

Procure por tracebacks de Python ou outras mensagens de erro explícitas que ocorreram imediatamente antes da mensagem final "hook failed". Um traceback revelará o arquivo exato e a linha de código que falhou, fornecendo uma pista crucial sobre a causa raiz (por exemplo, um TypeError, KeyError ou FileNotFoundError).

### **4.2. Fase 2: Forense Interativa de Hooks com juju debug-hooks**

Se a análise de logs não for conclusiva, a próxima etapa é usar juju debug-hooks, uma ferramenta poderosa que permite "interceptar" a execução de um hook e obter um shell interativo dentro do ambiente de execução do hook.28

1. **Inicie a Sessão de Depuração:** Execute o seguinte comando para observar o hook específico na unidade com falha:  
   Bash  
   juju debug-hooks haproxy/0 reverseproxy-relation-changed

   Isso abrirá uma sessão tmux no seu terminal e aguardará o acionamento do hook.

2. **Re-acione a Falha:** Para que o hook seja interceptado, você precisa fazer com que o Juju tente executá-lo novamente. A maneira mais limpa de fazer isso é resolver o estado de erro atual, o que fará com que o Juju retente o hook falho:  
   Bash  
   juju resolved haproxy/0

3. **Execute Manualmente o Hook:** Assim que o hook for acionado, a sessão tmux se tornará ativa e o colocará no diretório do charm (/var/lib/juju/agents/unit-haproxy-0/charm/). O ambiente estará totalmente configurado com todas as variáveis de ambiente do Juju. Agora você pode executar o script do hook manualmente para ver sua saída em tempo real:

./hooks/reverseproxy-relation-changed  
\`\`\`  
Qualquer erro, incluindo tracebacks completos de Python, será impresso diretamente no seu console. Isso fornece a visão mais clara possível da falha, eliminando qualquer suposição.

#### **Tabela 1: Ferramentas Essenciais de Depuração de Hooks do Juju**

A tabela a seguir resume as ferramentas e variáveis de ambiente mais importantes disponíveis dentro de uma sessão juju debug-hooks, essenciais para a fase de validação de dados.

| Ferramenta / Variável                   | Descrição                                                                            | Exemplo de Uso                                              |
| :-------------------------------------- | :----------------------------------------------------------------------------------- | :---------------------------------------------------------- |
| relation-ids \<endpoint\>               | Lista os IDs únicos para todas as relações em um determinado endpoint.               | relation-ids reverseproxy                                   |
| relation-list \-r \<rel-id\>            | Lista todas as unidades remotas que participam de uma relação específica.            | relation-list \-r reverseproxy:12                           |
| relation-get \-r \<rel-id\> \- \<unit\> | Exibe todos os dados de chave-valor de uma unidade remota específica em uma relação. | relation-get \-r reverseproxy:12 \- landscape-server/0      |
| config-get \<key\>                      | Recupera o valor de uma opção de configuração do charm.                              | config-get services                                         |
| juju-log \<message\>                    | Escreve uma mensagem no log de depuração do Juju para a unidade.                     | juju-log "Verificando certificado SSL."                     |
| $JUJU_REMOTE_UNIT                       | Variável de ambiente que contém o nome da unidade que acionou o evento.              | relation-get \-r reverseproxy:12 hostname $JUJU_REMOTE_UNIT |

### **4.3. Fase 3: Validação de Dados da Relação em Tempo Real**

Dentro da sessão debug-hooks, antes de executar o hook falho, você pode usar as ferramentas da Tabela 1 para inspecionar os dados que estão sendo passados pela relação. Este é o passo que valida o "contrato" de dados.

1. **Obtenha o ID da Relação:** relation-ids reverseproxy (ex: reverseproxy:12).
2. **Liste as Unidades Remotas:** relation-list \-r reverseproxy:12 (ex: landscape-server/0).
3. **Inspecione os Dados:** relation-get \-r reverseproxy:12 \- landscape-server/0.

Analise a saída deste último comando. Ela corresponde ao esquema esperado?

- Os dados do certificado SSL estão presentes e parecem ser uma string base64 válida?
- As chaves hostname e port estão presentes e corretas?
- A estrutura geral dos dados está correta (por exemplo, uma lista de serviços, se aplicável)?

Este passo permite confirmar ou refutar diretamente as hipóteses de causa raiz da Seção 3\.

### **4.4. Fase 4: Intervenção e Recuperação**

Com um diagnóstico claro em mãos, a intervenção pode ser realizada.

1. **Aplique a Correção:** A correção dependerá da causa raiz identificada:
   - **Problema de SSL:** Forneça o certificado e a chave via configuração. Lembre-se de que os valores devem ser codificados em base64.  
     Bash  
     CERT=$(sudo base64 \-w 0 /path/to/cert.pem)  
     KEY=$(sudo base64 \-w 0 /path/to/key.pem)  
     juju config haproxy ssl_cert="$CERT" ssl\_key="$KEY"

   - **Problema de Configuração:** Se outra configuração estiver incorreta, use juju config \<aplicação\> \<chave\>=\<valor\>.
   - **Bug no Charm:** Se a análise indicar um bug no próprio script do hook, a solução pode ser atualizar o charm para uma revisão mais recente que contenha a correção: juju upgrade-charm haproxy \--channel=stable.

2. **Limpe o Estado de Erro:** Depois de aplicar a correção, a unidade permanecerá em estado de error. O comando juju resolved informa ao agente Juju que o problema foi resolvido manualmente e que ele deve tentar executar novamente o hook que falhou.25  
   Bash  
   juju resolved haproxy/0

   O agente Juju irá então reexecutar hooks/reverseproxy-relation-changed. Com a causa raiz corrigida, o hook deve agora ser concluído com sucesso, e a unidade deve transitar para o estado active.

## **Seção 5: Recomendações e Melhores Práticas Preventivas**

Resolver um erro é reativo; prevenir sua ocorrência é proativo. As seguintes melhores práticas ajudarão a construir implantações Juju mais robustas e previsíveis, minimizando a probabilidade de encontrar falhas de hook complexas no futuro.

### **5.1. Adote uma Estratégia de Implantação Declarativa e Versionada**

A inconsistência observada entre implantações via CLI e GUI sugere fortemente que o processo de implantação manual e interativo é uma fonte de erro.7

- **Adote o bundle.yaml:** É fortemente recomendado evitar o uso da Juju GUI para implantações de produção ou qualquer ambiente que exija repetibilidade. Todas as implantações devem ser definidas declarativamente em um arquivo bundle.yaml.3 Este arquivo deve ser tratado como código: armazenado em um sistema de controle de versão (como Git), revisado por pares e usado como a única fonte da verdade para a arquitetura da aplicação. Isso garante implantações idênticas e auditáveis, eliminando o desvio de configuração que pode surgir de um processo manual.
- **Exemplo de bundle.yaml para HA:**  
  YAML  
  series: jammy  
  applications:  
   haproxy:  
   charm: haproxy  
   channel: stable  
   num_units: 3  
   expose: true  
   options:  
   ssl_cert: "..." \# Insira o certificado codificado em base64 aqui  
   ssl_key: "..." \# Insira a chave privada codificada em base64 aqui  
   landscape-server:  
   charm: landscape-server  
   channel: stable  
   num_units: 3  
   postgresql:  
   charm: postgresql  
   channel: "14/stable"  
   num_units: 3  
   rabbitmq-server:  
   charm: rabbitmq-server  
   channel: "3.9/stable"  
   num_units: 3  
  relations:  
   \- \[landscape-server, postgresql\]  
   \- \[landscape-server, rabbitmq-server\]  
   \- \[landscape-server, haproxy\]

### **5.2. Gerenciamento Proativo de Certificados SSL**

Não dependa de valores padrão ou da inferência de configuração para um componente tão crítico quanto o SSL.

- **Configuração Explícita:** Sempre configure explicitamente o charm haproxy com o certificado e a chave SSL necessários, seja através de juju config ou, preferencialmente, na seção options do bundle.yaml, como mostrado acima.3 Isso remove qualquer ambiguidade e garante que o certificado esteja disponível para o charm desde o início do seu ciclo de vida.
- **Uso de Charms de Certificado:** Para ambientes de produção, a melhor prática é integrar o haproxy com um charm de gerenciamento de certificados, como o letsencrypt-lego-operator. Isso automatiza completamente o processo de obtenção, renovação e fornecimento de certificados, eliminando a necessidade de etapas manuais propensas a erros.

### **5.3. Gerenciamento de Charms e Canais**

A evolução dos charms pode introduzir tanto correções de bugs quanto novas incompatibilidades.

- **Fixação de Revisões:** Embora implantar do canal stable seja um bom padrão, para sistemas de produção críticos, é prudente fixar as revisões específicas dos charms no bundle.yaml (por exemplo, revision: 75 para o haproxy, como visto em implantações documentadas 3). Isso impede que atualizações inesperadas de charms (seja por um  
  juju upgrade-charm ou por uma nova versão no canal) introduzam mudanças de comportamento ou bugs que quebrem a integração. As atualizações devem ser um processo controlado e testado.
- **Ambientes de Staging e Testes:** Antes de implantar um novo bundle ou uma nova revisão de charm em produção, ele deve ser exaustivamente testado em um modelo de _staging_ separado, mas idêntico. Este processo teria capturado a falha do hook reverseproxy-relation-changed em um ambiente seguro, permitindo a investigação e resolução sem impactar os serviços de produção.

### **5.4. Preparando para o Futuro: O Operator Framework**

Muitos charms mais antigos, incluindo algumas versões do haproxy, foram escritos usando scripts de hook baseados em shell. A abordagem moderna para o desenvolvimento de charms é o Operator Framework, baseado em Python. Charms desenvolvidos com este framework tendem a ser mais robustos, com melhor tratamento de erros (por exemplo, entrando em um BlockedStatus com uma mensagem clara em vez de simplesmente falhar), testes unitários mais fáceis e esquemas de dados de relação mais bem definidos. Ao avaliar charms para projetos futuros, dar preferência àqueles construídos com o Operator Framework pode levar a uma experiência operacional mais estável e depurável.

## **Apêndice: Referência Rápida de Comandos de Depuração do Juju**

| Comando                            | Descrição e Uso no Contexto da Falha                                                                                                                                                      |
| :--------------------------------- | :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| juju status \--relations           | Fornece uma visão geral completa do modelo, incluindo o estado das unidades, mensagens de erro e o status de todas as relações. Essencial para a triagem inicial.                         |
| juju debug-log \[flags\]           | Transmite os logs de depuração de todos os agentes Juju. Use com \--replay, \--level=ERROR e \--include=\<unit\> para isolar rapidamente a causa da falha.                                |
| juju debug-hooks \<unit\> \[hook\] | Intercepta a execução de um hook, fornecendo um shell interativo no ambiente exato do hook para depuração manual e inspeção em tempo real. A ferramenta mais poderosa para este problema. |
| juju resolved \<unit\>             | Informa ao Juju que um erro de hook foi resolvido manualmente, instruindo o agente a tentar novamente a execução do hook falho. O passo final da recuperação.                             |
| juju config \<app\> \[key=value\]  | Permite visualizar e modificar a configuração de uma aplicação. Usado para corrigir configurações incorretas (especialmente ssl_cert e ssl_key no haproxy).                               |
| juju integrate \<app1\> \<app2\>   | Cria uma relação entre duas aplicações. Usado para restabelecer a relação após a remoção para fins de depuração com juju debug-hooks.                                                     |

#### **Referências citadas**

1. How to install Landscape Server with Juju \- Landscape documentation, acessado em outubro 5, 2025, [https://documentation.ubuntu.com/landscape/how-to-guides/landscape-installation-and-set-up/juju-installation/](https://documentation.ubuntu.com/landscape/how-to-guides/landscape-installation-and-set-up/juju-installation/)
2. Juju bundles and Quickstart: create a cloud environment in seconds | Canonical, acessado em outubro 5, 2025, [https://canonical.com/blog/juju-bundles-and-quickstart-create-an-entire-cloud-environment-in-seconds](https://canonical.com/blog/juju-bundles-and-quickstart-create-an-entire-cloud-environment-in-seconds)
3. How to install and configure Landscape for high-availability deployments, acessado em outubro 5, 2025, [https://documentation.ubuntu.com/landscape/how-to-guides/landscape-installation-and-set-up/juju-ha-installation/](https://documentation.ubuntu.com/landscape/how-to-guides/landscape-installation-and-set-up/juju-ha-installation/)
4. Deploy Landscape Scalable using Charmhub \- The Open Operator Collection, acessado em outubro 5, 2025, [https://charmhub.io/landscape-scalable](https://charmhub.io/landscape-scalable)
5. Deploying Web Applications using Juju – (Part 3/3) \- Canonical, acessado em outubro 5, 2025, [https://canonical.com/blog/deploying-web-applications-using-juju-part-33](https://canonical.com/blog/deploying-web-applications-using-juju-part-33)
6. canonical/haproxy-operator \- charm repository. \- GitHub, acessado em outubro 5, 2025, [https://github.com/canonical/haproxy-operator](https://github.com/canonical/haproxy-operator)
7. HAproxy: "reverseproxy-relation-changed" in Landscape Dense Maas bundle \- Ask Ubuntu, acessado em outubro 5, 2025, [https://askubuntu.com/questions/906763/haproxy-reverseproxy-relation-changed-in-landscape-dense-maas-bundle](https://askubuntu.com/questions/906763/haproxy-reverseproxy-relation-changed-in-landscape-dense-maas-bundle)
8. Juju | About, acessado em outubro 5, 2025, [https://juju.is/overview](https://juju.is/overview)
9. Deploy HAProxy using Charmhub \- The Open Operator Collection, acessado em outubro 5, 2025, [https://charmhub.io/haproxy/integrations](https://charmhub.io/haproxy/integrations)
10. How do I add a relationship between two charms to pass information between them?, acessado em outubro 5, 2025, [https://askubuntu.com/questions/504482/how-do-i-add-a-relationship-between-two-charms-to-pass-information-between-them](https://askubuntu.com/questions/504482/how-do-i-add-a-relationship-between-two-charms-to-pass-information-between-them)
11. Deploy Landscape Server using Charmhub \- The Open Operator Collection, acessado em outubro 5, 2025, [https://charmhub.io/landscape-server/integrations](https://charmhub.io/landscape-server/integrations)
12. Relation (integration) \- Juju \- Ubuntu documentation, acessado em outubro 5, 2025, [https://documentation.ubuntu.com/juju/3.6/reference/relation/](https://documentation.ubuntu.com/juju/3.6/reference/relation/)
13. The hook environment, hook tools and how hooks are run \- doc \- Charmhub, acessado em outubro 5, 2025, [https://discourse.charmhub.io/t/the-hook-environment-hook-tools-and-how-hooks-are-run/1047](https://discourse.charmhub.io/t/the-hook-environment-hook-tools-and-how-hooks-are-run/1047)
14. Hook \- Juju \- Ubuntu documentation, acessado em outubro 5, 2025, [https://documentation.ubuntu.com/juju/3.6/reference/hook/](https://documentation.ubuntu.com/juju/3.6/reference/hook/)
15. jrwren \- lazy dawg evarlast \- Jay R. Wren, acessado em outubro 5, 2025, [http://jrwren.wrenfam.com/blog/author/jrwren/index.html](http://jrwren.wrenfam.com/blog/author/jrwren/index.html)
16. Using the haproxy charm \- Jay R. Wren, acessado em outubro 5, 2025, [http://jrwren.wrenfam.com/blog/2017/02/14/using-the-haproxy-charm/index.html](http://jrwren.wrenfam.com/blog/2017/02/14/using-the-haproxy-charm/index.html)
17. What is a Juju relation and what purpose do they serve? \[Part 2\] \- Charmhub, acessado em outubro 5, 2025, [https://discourse.charmhub.io/t/what-is-a-juju-relation-and-what-purpose-do-they-serve-part-2/2378](https://discourse.charmhub.io/t/what-is-a-juju-relation-and-what-purpose-do-they-serve-part-2/2378)
18. relation-get \- Juju \- Ubuntu documentation, acessado em outubro 5, 2025, [https://documentation.ubuntu.com/juju/3.6/reference/hook-command/list-of-hook-commands/relation-get/](https://documentation.ubuntu.com/juju/3.6/reference/hook-command/list-of-hook-commands/relation-get/)
19. \[Tutorial\] Relations with Juju \- Charmhub, acessado em outubro 5, 2025, [https://discourse.charmhub.io/t/tutorial-relations-with-juju/3632](https://discourse.charmhub.io/t/tutorial-relations-with-juju/3632)
20. SSL Node.js Charms with Haproxy \- Ask Ubuntu, acessado em outubro 5, 2025, [https://askubuntu.com/questions/600880/ssl-node-js-charms-with-haproxy](https://askubuntu.com/questions/600880/ssl-node-js-charms-with-haproxy)
21. Bug \#2029385 “/charm/data/openssl.cnf No such file or directory” \- Launchpad Bugs, acessado em outubro 5, 2025, [https://bugs.launchpad.net/bugs/2029385](https://bugs.launchpad.net/bugs/2029385)
22. Bug \#1800687 “charm does not report landscape client certificate...” \- Launchpad Bugs, acessado em outubro 5, 2025, [https://bugs.launchpad.net/bugs/1800687](https://bugs.launchpad.net/bugs/1800687)
23. juju status \- Ubuntu documentation, acessado em outubro 5, 2025, [https://documentation.ubuntu.com/juju/3.6/reference/juju-cli/list-of-juju-cli-commands/status/](https://documentation.ubuntu.com/juju/3.6/reference/juju-cli/list-of-juju-cli-commands/status/)
24. How to manage relations \- Juju \- Ubuntu documentation, acessado em outubro 5, 2025, [https://documentation.ubuntu.com/juju/3.6/howto/manage-relations/](https://documentation.ubuntu.com/juju/3.6/howto/manage-relations/)
25. Troubleshoot your Juju deployment \- Ubuntu documentation, acessado em outubro 5, 2025, [https://documentation.ubuntu.com/juju/3.6/howto/manage-your-juju-deployment/troubleshoot-your-juju-deployment/](https://documentation.ubuntu.com/juju/3.6/howto/manage-your-juju-deployment/troubleshoot-your-juju-deployment/)
26. juju debug-log \- Ubuntu documentation, acessado em outubro 5, 2025, [https://documentation.ubuntu.com/juju/3.6/reference/juju-cli/list-of-juju-cli-commands/debug-log/](https://documentation.ubuntu.com/juju/3.6/reference/juju-cli/list-of-juju-cli-commands/debug-log/)
27. How to use Juju to debug logs \- doc \- Charmhub, acessado em outubro 5, 2025, [https://discourse.charmhub.io/t/how-to-use-juju-to-debug-logs/10806](https://discourse.charmhub.io/t/how-to-use-juju-to-debug-logs/10806)
28. How do I debug juju hooks? \- Ask Ubuntu, acessado em outubro 5, 2025, [https://askubuntu.com/questions/614063/how-do-i-debug-juju-hooks](https://askubuntu.com/questions/614063/how-do-i-debug-juju-hooks)
29. juju debug-hooks \- Ubuntu documentation, acessado em outubro 5, 2025, [https://documentation.ubuntu.com/juju/3.6/reference/juju-cli/list-of-juju-cli-commands/debug-hooks/](https://documentation.ubuntu.com/juju/3.6/reference/juju-cli/list-of-juju-cli-commands/debug-hooks/)
30. How do I list all the relation variables and debug them interactively? \- Ask Ubuntu, acessado em outubro 5, 2025, [https://askubuntu.com/questions/221469/how-do-i-list-all-the-relation-variables-and-debug-them-interactively](https://askubuntu.com/questions/221469/how-do-i-list-all-the-relation-variables-and-debug-them-interactively)
31. Juju debug-hooks, how to run hook in debug terminal or get more information? \- Ask Ubuntu, acessado em outubro 5, 2025, [https://askubuntu.com/questions/362687/juju-debug-hooks-how-to-run-hook-in-debug-terminal-or-get-more-information](https://askubuntu.com/questions/362687/juju-debug-hooks-how-to-run-hook-in-debug-terminal-or-get-more-information)
32. juju resolved \- Ubuntu documentation, acessado em outubro 5, 2025, [https://documentation.ubuntu.com/juju/3.6/reference/juju-cli/list-of-juju-cli-commands/resolved/](https://documentation.ubuntu.com/juju/3.6/reference/juju-cli/list-of-juju-cli-commands/resolved/)
33. Canonical Juju \- Cannot resolve a blocked unit \- Launchpad Bugs, acessado em outubro 5, 2025, [https://bugs.launchpad.net/bugs/1478983](https://bugs.launchpad.net/bugs/1478983)
34. Deploy Landscape Scalable using Charmhub \- The Open Operator Collection, acessado em outubro 5, 2025, [https://charmhub.io/landscape-scalable/configurations/haproxy](https://charmhub.io/landscape-scalable/configurations/haproxy)
35. Deploy HAProxy using Charmhub \- The Open Operator Collection, acessado em outubro 5, 2025, [https://charmhub.io/haproxy/configurations](https://charmhub.io/haproxy/configurations)
