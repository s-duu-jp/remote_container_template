# Get container image
# https://hub.docker.com/_/microsoft-vscode-devcontainers
ARG NODE_VAR
FROM mcr.microsoft.com/vscode/devcontainers/typescript-node:0-${NODE_VAR}

# Install initial packages
RUN apt-get update \
  && apt-get -y install git