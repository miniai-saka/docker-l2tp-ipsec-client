# docker-l2tp-ipsec-client

Docker コンテナの IPv4 通信を L2TP/IPsec VPN に流すクライアントです。VPN コンテナとネットワークを共有すれば、別のコンテナの通信も同じ VPN を通せます。

## 動作環境

- Linux x86-64 の Docker ホストで、rootful の Docker Engine と `docker compose up --wait` に対応する Docker Compose を使います。ホストのカーネルには PPP、IPsec、iptables の `policy` マッチが必要です。Compose はコンテナに `/dev/ppp` と `NET_ADMIN` を渡します。
- Docker ブリッジのゲートウェイ経由で VPN サーバーに IPv4 で到達できる構成が必要です。サーバーは IKEv1 の事前共有鍵認証、IPsec のトランスポートモード、PPP の MS-CHAPv2 に対応している必要があります。IKEv1 は IETF で非推奨とされています。[RFC 9395](https://www.rfc-editor.org/rfc/rfc9395.html)

## 設定と起動

Docker ホストでリポジトリを取得します。

```bash
git clone https://github.com/miniai-saka/docker-l2tp-ipsec-client.git
cd docker-l2tp-ipsec-client
```

設定には Bash と `getent ahostsv4` を使います。`vpn.example.com` を接続先のホスト名または IPv4 アドレスに置き換えて実行してください。

```bash
test -c /dev/ppp || sudo modprobe ppp_generic
bash configure.sh vpn.example.com
docker compose up --build --wait --wait-timeout 100
```

入力する順番は、PPP のユーザー名、PPP のパスワード、IPsec の事前共有鍵です。パスワードと事前共有鍵は入力時に非表示です。接続先の IPv4 アドレスは `.env` に保存します。認証情報は `secrets/` にアクセス権 `600` で保存し、コンテナに読み取り専用で渡します。

DNS は `resolv.conf` にある `1.1.1.1` と `1.0.0.1` を使います。VPN 側で指定された DNS があれば、起動前にこのファイルを書き換えてください。

## 接続の確認

```bash
docker compose ps
docker compose exec -T vpn swanctl --list-sas --child l2tp
docker compose exec -T vpn ip -4 route get 1.1.1.1
```

`vpn` が `healthy` になり、IPsec に `INSTALLED`、経路に `dev ppp0` が表示されれば接続できています。接続が上がらないときは `docker compose logs --tail=100 vpn` でログを確認してください。

インターネットに出られる VPN なら、次のコマンドで名前解決と HTTPS 通信も確認できます。

```bash
docker compose exec -T vpn curl -4fsS --max-time 10 \
  -o /dev/null -w '%{http_code}\n' https://example.com/
```

## 別のコンテナから使う

同じ `compose.yaml` に VPN を使いたいサービスを定義し、そのサービスに次の設定を加えます。利用側の `networks` は外し、`vpn` のネットワークを共有します。利用側は `vpn` のヘルスチェックが通ってから起動します。[Docker Compose のサービス設定](https://docs.docker.com/reference/compose-file/services/#network_mode)

```yaml
network_mode: service:vpn
depends_on:
  vpn:
    condition: service_healthy
cap_drop:
  - NET_RAW
volumes:
  - ./resolv.conf:/etc/resolv.conf:ro
```

通信の制御は VPN 側に任せるため、利用側は `NET_ADMIN` や `privileged` を付けずに動かしてください。VPN コンテナを作り直したときは、利用側のコンテナも作り直してください。

## 停止

```bash
docker compose down
```

接続先のホスト名は、設定時に Docker ホストで IPv4 アドレスに解決します。DDNS などでアドレスが変わったときは、停止してから `configure.sh` と起動コマンドを実行し直してください。

<details>
<summary>接続方式と通信経路</summary>

- IKE は AES-128-CBC、HMAC-SHA1、MODP 2048、ESP は AES-128-CBC と HMAC-SHA1 を使います。PPP の MTU と MRU は 1280 です。
- VPN サーバーとの IKE、ESP、IPsec で保護された L2TP は Docker ブリッジの `eth0` を使います。通常の外向き IPv4 通信と DNS は `ppp0` を通ります。
- PPP の切断中はファイアウォールで通常の外向き通信を遮断し、同じコンテナ内で再接続を試みます。
- Docker の内蔵 DNS `127.0.0.11` は遮断します。IPv6 はコンテナ内で無効です。[Docker の DNS 仕様](https://docs.docker.com/engine/network/#dns-services)

</details>

## 出典とライセンス

このリポジトリのファイルは MIT License で公開します。[LICENSE](LICENSE)

ベースイメージには Alpine Linux 3.23 を使います。イメージのビルド時に入るパッケージには、それぞれのライセンスが適用されます。[strongSwan](https://pkgs.alpinelinux.org/package/v3.23/main/x86_64/strongswan) · [xl2tpd](https://pkgs.alpinelinux.org/package/v3.23/main/x86_64/xl2tpd) · [ppp](https://pkgs.alpinelinux.org/package/v3.23/main/x86_64/ppp)
