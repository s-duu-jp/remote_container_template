# --------------------------------------------------------------
# global
# --------------------------------------------------------------
FROM mcr.microsoft.com/vscode/devcontainers/base:ubuntu

# User settings
ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=$USER_UID

# Remap UID/GID if non-default values are passed at build time
RUN if [ "$USER_UID" != "1000" ] || [ "$USER_GID" != "1000" ]; then \
    groupmod -o -g "$USER_GID" "$USERNAME" || addgroup -g "$USER_GID" "$USERNAME"; \
    usermod -o -u "$USER_UID" -g "$USER_GID" "$USERNAME" || adduser --uid "$USER_UID" --gid "$USER_GID" --disabled-password --gecos "" "$USERNAME"; \
    chown -R $USER_UID:$USER_GID /home/$USERNAME; \
    fi

WORKDIR /workspace

USER ${USERNAME}

# GitHub CLI repo + all apt packages in one layer
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && sudo apt update && sudo apt install -y unzip curl gh \
    && sudo apt-get clean && sudo rm -rf /var/lib/apt/lists/*

# --------------------------------------------------------------
# Node.js and Claude Code
# --------------------------------------------------------------

# nvm — https://github.com/nvm-sh/nvm/releases
ARG NVM_VERSION=0.40.4
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh | bash

# Node.js — https://github.com/nodejs/node/releases
ARG NODE_VERSION=24.15.0
RUN bash -i -c 'nvm install ${NODE_VERSION}'

# Claude Code
RUN bash -i -c 'npm install -g @anthropic-ai/claude-code' \
    && mkdir -p /home/${USERNAME}/.claude
