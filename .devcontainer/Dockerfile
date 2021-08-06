# Get container image
# https://hub.docker.com/_/microsoft-vscode-devcontainers
ARG NODE_VAR
FROM mcr.microsoft.com/vscode/devcontainers/typescript-node:0-${NODE_VAR}

# [Optional] Update UID/GID if needed
ARG USER_SID
ARG USER_UID
ARG USER_GID
RUN if [ "$USER_GID" != "1000" ] || [ "$USER_UID" != "1000" ]; then \
  groupmod --gid $USER_GID $USER_SID \
  && usermod --uid $USER_UID --gid $USER_GID $USER_SID \
  && chown -R $USER_UID:$USER_GID /home/$USER_SID; \
  fi

# Install initial packages
RUN apt-get update \
  && apt-get -y install git \
  && npm install -g prettier \
  && npm install -g eslint \
  && npm install -g eslint-config-prettier
