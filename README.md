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

1. プロジェクトディレクトリをワークスペースとして VSCODE を開きなおします

      ```bash
      $ cd duu_chat \
      && code .
      ```

1. Remote Container 用の環境変数ファイルを複製します

      ```bash
      $ cp -p .devcontainer/.env_example .devcontainer/.env
      ```

1. 複製した.env ファイルを編集して保存します

      ```bash
      # Project Name
      COMPOSE_PROJECT_NAME=*****　← (例：web_example)

      # Node Version
      # https://nodejs.org/
      NODE_VERSION=14
      ```

      | パラメータ           | 内容                                        |
      | -------------------- | ------------------------------------------- |
      | COMPOSE_PROJECT_NAME | これから構築される Docker のコンテナ名      |
      | NODE_VERSION         | プロジェクトで利用する Node.js のバージョン |


1. Docker コンテナの構築を行います

   1. `F1 キー`でコマンドパレットを開く

   1. 「`Remote-Containers: Rebuild and Reopen in Container`」を選択

   1. あとは Docker コンテナの Build が始まり自動的に開発環境が構築されます。
