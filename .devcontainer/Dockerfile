ARG USERNAME
ARG USER_UID
ARG USER_GID

# https://hub.docker.com/_/microsoft-vscode-devcontainers
FROM mcr.microsoft.com/vscode/devcontainers/typescript-node:0.205.2-20-buster

#--------------------------------------------------------
# Update UID/GID if needed
#--------------------------------------------------------
RUN if [ ${USER_GID} != "1000" ] || [ ${USER_UID} != "1000" ]; then \
    groupmod --gid ${USER_GID} ${USERNAME} \
    && usermod --uid ${USER_UID} --gid ${USER_GID} ${USERNAME} \
    && chown -R ${USER_UID}:${USER_GID} /${USERNAME}; \
  fi

# Switch User
RUN mkdir -p /workspace && chown -R node:node /workspace
USER node
