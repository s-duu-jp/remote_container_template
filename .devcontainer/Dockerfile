ARG NODE_VAR
ARG USERNAME
ARG USER_UID
ARG USER_GID

# Get container image
# https://hub.docker.com/_/microsoft-vscode-devcontainers
FROM mcr.microsoft.com/vscode/devcontainers/typescript-node:0-${NODE_VAR}

#--------------------------------------------------------
# Update UID/GID if needed
#--------------------------------------------------------
RUN if [ ${USER_GID} != "1000" ] || [ ${USER_UID} != "1000" ]; then \
    groupmod --gid ${USER_GID} ${USERNAME} \
    && usermod --uid ${USER_UID} --gid ${USER_GID} ${USERNAME} \
    && chown -R ${USER_UID}:${USER_GID} /${USERNAME}; \
  fi