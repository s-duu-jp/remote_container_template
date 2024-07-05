# ベースとなるDockerイメージを指定
FROM mcr.microsoft.com/vscode/devcontainers/base:ubuntu

# ユーザー情報の設定
ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=$USER_UID

# UID/GIDがデフォルト値でない場合にユーザーとグループを更新または作成
RUN if [ "$USER_UID" != "1000" ] || [ "$USER_GID" != "1000" ]; then \
    groupmod -o -g "$USER_GID" "$USERNAME" || addgroup -g "$USER_GID" "$USERNAME"; \
    usermod -o -u "$USER_UID" -g "$USER_GID" "$USERNAME" || adduser --uid "$USER_UID" --gid "$USER_GID" --disabled-password --gecos "" "$USERNAME"; \
    chown -R $USER_UID:$USER_GID /home/$USERNAME; \
    fi

# パッケージリストを更新
RUN apt update

# ワークスペースディレクトリを設定
WORKDIR /workspace
