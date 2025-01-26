# Specify the base Docker image
FROM mcr.microsoft.com/vscode/devcontainers/base:ubuntu

# Set user information
ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=$USER_UID

# Update or create user and group if UID/GID are not default values
RUN if [ "$USER_UID" != "1000" ] || [ "$USER_GID" != "1000" ]; then \
    groupmod -o -g "$USER_GID" "$USERNAME" || addgroup -g "$USER_GID" "$USERNAME"; \
    usermod -o -u "$USER_UID" -g "$USER_GID" "$USERNAME" || adduser --uid "$USER_UID" --gid "$USER_GID" --disabled-password --gecos "" "$USERNAME"; \
    chown -R $USER_UID:$USER_GID /home/$USERNAME; \
    fi

# Set workspace directory
WORKDIR /workspace

# Switch to the specified user
USER ${USERNAME}
