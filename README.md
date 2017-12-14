candy-pi-lite-service
===
[![GitHub release](https://img.shields.io/github/release/CANDY-LINE/candy-pi-lite-service.svg)](https://github.com/CANDY-LINE/candy-pi-lite-service/releases/latest)
[![License ASL 2.0](https://img.shields.io/github/license/CANDY-LINE/candy-pi-lite-service.svg)](https://opensource.org/licenses/Apache-2.0)

candy-pi-lite-serviceは、Raspberry Pi上で動作するCANDY Pi Liteを動作させるためのシステムサービス（Raspberry Pi上で自動的に動作するソフトウェア）です。

candy-pi-lite-serviceや、CANDY Pi Liteに関する説明については、専用の[利用ガイド](https://candy-line.gitbooks.io/candy-pi-lite/content/)をご覧ください。

ℹ️ 使い方の質問、不具合のご報告やご意見などは、[CANDY LINEフォーラム](https://forums.candy-line.io/c/candy-pi-lite)をご利用ください。

ℹ️ 不具合のご報告に関しては、GitHubのIssuesをご利用いただいても構いません。

# 管理者向け
## モジュールリリース時の注意
1. [`install.sh`](install.sh)内の`VERSION=`にあるバージョンを修正してコミットする
1. 履歴を追記、修正してコミットする
1. （もし必要があれば）パッケージング
```bash
$ ./install.sh pack
```

## 開発用インストール動作確認
### パッケージング

```bash
$ ./install.sh pack
(scp to RPi then ssh)
```

`raspberrypi.local`でアクセスできる場合は以下のコマンドも利用可能。
```bash
$ make
(enter RPi password)
```

ホストを指定するときは、`PI_HOST`を指定する。
```bash
$ make PI_HOST=shinycandypi.local
(enter ssh user password)
```

ユーザー名を指定するときは、`PI_USER`を指定する。
```bash
$ make PI_USER=linaro PI_HOST=192.168.1.10
(enter ssh user password)
```

### 動作確認 (RPi)

```bash
$ VERSION=1.7.3 && rm -fr tmp && mkdir tmp && cd tmp && \
  tar zxf ~/candy-pi-lite-service-${VERSION}.tgz
$ time sudo SRC_DIR=$(pwd) DEBUG=1 ./install.sh
$ time sudo SRC_DIR=$(pwd) DEBUG=1 CONFIGURE_STATIC_IP_ON_BOOT=1 ./install.sh
$ time sudo SRC_DIR=$(pwd) DEBUG=1 CANDY_RED=0 BOOT_APN=soracom.io ./install.sh
$ time sudo SRC_DIR=$(pwd) DEBUG=1 CANDY_RED=0 BOOT_APN=soracom.io ENABLE_WATCHDOG=0 ./install.sh
$ time sudo SRC_DIR=$(pwd) DEBUG=1 CANDY_RED=0 CONFIGURE_STATIC_IP_ON_BOOT=1 BOOT_APN=soracom.io ./install.sh
$ time sudo SRC_DIR=$(pwd) DEBUG=1 CANDY_RED=0 BOOT_APN=soracom.io PPP_PING_INTERVAL_SEC=5 ./install.sh

$ time sudo /opt/candy-line/candy-pi-lite/uninstall.sh
```

# ライセンス

Copyright (c) 2017 [CANDY LINE INC.](https://www.candy-line.io)

[Apache Software License 2.0](LICENSE)
