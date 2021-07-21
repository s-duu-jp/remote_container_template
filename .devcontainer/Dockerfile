ARG CONTAINER_OS
FROM mcr.microsoft.com/vscode/devcontainers/base:${CONTAINER_OS}

# Install NodeJS
ARG NODE_VERSION
RUN apt-get update \
 && apt-get install -y build-essential libssl-dev \
 && curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.38.0/install.sh | bash \
 && . ~/.bashrc \
 && nvm install v${NODE_VERSION}

# Install packages
RUN apt-get update \ 
  && apt install -y make gcc g++ npm git direnv \
  && npm install -g prettier \
  && npm install -g eslint \
  && npm install -g eslint-config-prettier