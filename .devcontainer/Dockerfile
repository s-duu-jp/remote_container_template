ARG VARIANT=$VARIANT
FROM mcr.microsoft.com/vscode/devcontainers/typescript-node:0-${VARIANT}

ARG USER_UID=$USER_UID
ARG USER_GID=$USER_GID
ARG USERNAME=root

# [Optional] Update UID/GID if needed
RUN if [ "$USER_GID" != "1000" ] || [ "$USER_UID" != "1000" ]; then \
        groupmod --gid $USER_GID $USERNAME \
        && usermod --uid $USER_UID --gid $USER_GID $USERNAME \
        && chown -R $USER_UID:$USER_GID /home/$USERNAME; \
    fi

# install yarn
ENV APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE=1
RUN npm config set user root
RUN curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add - \
    && echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list \
    && apt-get update \
    && apt-get install -y yarn

# Install npm packages
RUN apt-get -y install git \
  && npm install -g prettier \
  && npm install -g eslint \
  && npm install -g eslint-config-prettier