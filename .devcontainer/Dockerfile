ARG USERNAME
ARG USER_UID
ARG USER_GID

# https://hub.docker.com/_/microsoft-vscode-devcontainers
FROM mcr.microsoft.com/vscode/devcontainers/typescript-node:0.204.8-16-buster

#--------------------------------------------------------
# Update UID/GID if needed
#--------------------------------------------------------
RUN if [ ${USER_GID} != "1000" ] || [ ${USER_UID} != "1000" ]; then \
    groupmod --gid ${USER_GID} ${USERNAME} \
    && usermod --uid ${USER_UID} --gid ${USER_GID} ${USERNAME} \
    && chown -R ${USER_UID}:${USER_GID} /${USERNAME}; \
  fi

# change owner of directory
RUN mkdir -p /workspace && chown -R node:node /workspace

# StoryBook Conflicting回避用
RUN echo export NODE_ENV="development" >> /etc/profile