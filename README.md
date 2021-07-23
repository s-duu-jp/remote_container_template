# プロダクト名：Duu Chat

## **概要**

Docker リモートコンテナのテンプレートです。

---

## **前提条件**

お使いの環境が利用可能でない場合は[こちら](https://code.visualstudio.com/docs/remote/containers)を参考に事前作業を行ってください。

1. VSCode Remote Containers が利用可能である事

---

## **構築手順**

以下の手順に従って下さい。

1. 本リポジトリを git clone します

      ```bash
      $ git clone https://github.com/s-duu-jp/remote_container_template.git
      ```

1. 以下コマンドで新しいコンテナを複製起動します。

      注意：ここでは新しいコンテナ名を`hogehoge`とします
   ```bash
   $ arg="hogehoge" \
     && cp -rp remote_container_template ${arg} \
     && cd ${arg} \
     && rm -rf .git \
     && sed -i -e "s/\*\*\*/${arg}/g" .devcontainer/docker-compose.yml \
     && git init \
     && git add . \
     && git commit -m "first commit" \
     && code --folder-uri vscode-remote://dev-container+$(echo -n $(pwd) | xxd -p)/workspace
   ```
