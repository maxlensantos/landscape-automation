# Dockerfile
# Imagem de base, a mesma usada no seu .gitlab-ci.yml original
FROM ubuntu:22.04

# Autor da Imagem
LABEL maintainer="Seu Nome <seu-email@example.com>"
LABEL description="Imagem de CI/CD para o projeto Landscape Automation com Juju, LXD, Ansible e linters pré-instalados."

# Define o frontend como não interativo para evitar que comandos apt travem
ENV DEBIAN_FRONTEND=noninteractive

# Instala todas as dependências do sistema, snaps e limpa o cache do apt em uma única camada
RUN apt-get update -qq \
    && apt-get install -y --no-install-recommends \
        python3 \
        python3-pip \
        openssl \
        curl \
        jq \
        shellcheck \
        snapd \
        git \
    && rm -rf /var/lib/apt/lists/* \
    # Habilita e inicia o serviço snapd
    && systemctl enable snapd \
    && systemctl start snapd \
    # Instala Juju e LXD via Snap
    && snap install juju --classic \
    && snap install lxd \
    # Adiciona o grupo 'lxd'. O usuário 'gitlab-runner' será adicionado a ele no runtime.
    && groupadd --system lxd

# Instala as ferramentas Python (Ansible, Linters, Molecule) em uma única camada
RUN pip3 install --no-cache-dir \
    ansible-core \
    ansible-lint \
    yamllint \
    molecule \
    docker # Driver do Molecule para testes

# Instala as coleções Ansible necessárias
RUN ansible-galaxy collection install community.general

# Define um diretório de trabalho padrão (opcional)
WORKDIR /builds

# Define o comando padrão (opcional, pode ser útil para depuração)
CMD [ "/bin/bash" ]
