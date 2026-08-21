# NanoOps Server 单机部署（无 Docker）

本包面向 Linux x86_64/amd64，内含静态链接的服务端、Web 控制台、SQLite
以及 systemd 配置。目标目录固定为 `/data/nanoops`，不包含 Agent。

## 1. 上传并解压

在本地执行（替换服务器地址和包版本）：

```bash
scp nanoops-server-linux-amd64-0.4.10.tar.gz root@SERVER_IP:/data/
```

在服务器执行：

```bash
sudo install -d -m 0700 -o root -g root /data/nanoops
sudo tar -xzf /data/nanoops-server-linux-amd64-0.4.10.tar.gz \
  -C /data/nanoops --strip-components=1
cd /data/nanoops
sudo sha256sum -c SHA256SUMS
sudo bash install.sh
```

安装器会让你选择三个大于 1024 且互不相同的端口，并配置超级管理员。
建议先采用默认值：HTTP `18080`、Agent WebSocket `19100`、Agent gRPC
`39100`。当前不部署 Agent，因此云安全组和系统防火墙都不要放行这三个端口。

## 2. 首次访问

没有域名/TLS 时，不要把 HTTP 端口直接暴露到公网。使用 SSH 隧道：

```bash
ssh -L 18080:127.0.0.1:18080 root@SERVER_IP
```

然后在本机打开 `http://127.0.0.1:18080/dashboard/`。

正式公网访问应使用域名、nginx 和 HTTPS：

1. DNS A/AAAA 记录指向服务器。
2. 安装 nginx 和 certbot。
3. 复制 `nginx-nanoops.conf.example` 到 nginx 配置目录，替换域名；如果
   安装时修改了 HTTP 端口，同时修改 upstream 的 `127.0.0.1:18080`。
4. 检查并重载 nginx：`sudo nginx -t && sudo systemctl reload nginx`。
5. 申请证书：`sudo certbot --nginx -d nanoops.example.com`。
6. 云安全组只放行管理 SSH、TCP 80 和 TCP 443；保持应用三个端口关闭。

应用已经只信任来自本机回环地址的代理头，因此同机 nginx 转发的 HTTPS
请求会得到 Secure/HttpOnly/SameSite 会话 Cookie。若反向代理不在同一台
机器，必须在 `config.yaml` 的 `trusted_proxies` 中写它的精确 IP/CIDR。

## 3. 超级管理员账号和密码

安装器把以下值写入 `/data/nanoops/server.env`（`root:root`, `0600`）：

```text
NANOLINK_ADMIN_USERNAME="你的管理员用户名"
NANOLINK_ADMIN_PASSWORD="你的强密码"
NANOLINK_JWT_SECRET="随机生成的 32 字节以上密钥"
```

这两个管理员变量在每次启动时都是权威值：修改 env 文件并重启服务会同步
数据库中的管理员密码，同时撤销旧会话。推荐的密码轮换流程：

```bash
sudoedit /data/nanoops/server.env
sudo systemctl restart nanoops-server
```

如果你希望以后只在 Web 控制台改密码，在首次成功登录后可同时删除
`NANOLINK_ADMIN_USERNAME` 和 `NANOLINK_ADMIN_PASSWORD` 两行，再重启；现有
SQLite 管理员账号会保留。两行必须同时存在或同时删除。JWT 密钥不能删除，
也不要随意更换；更换会让所有现有登录会话失效。

## 4. 端口变更

修改 `/data/nanoops/server.env` 中的三个端口后执行：

```bash
sudo systemctl restart nanoops-server
sudo systemctl status nanoops-server --no-pager
```

如果修改 HTTP 端口，还要同步修改 nginx upstream 或 SSH 隧道。后续开始部署
Agent 时，再按需要开放 WebSocket/gRPC 之一；开放前应启用 TLS，gRPC 最好再
配置客户端 CA（mTLS），并用后台生成的独立 Agent Token，切勿复用管理员密码。

## 5. 日常运维

```bash
curl -fsS http://127.0.0.1:18080/api/health
sudo systemctl status nanoops-server --no-pager
sudo journalctl -u nanoops-server -f
sudo systemctl restart nanoops-server
sudo cp -a /data/nanoops/data /data/nanoops-backup-$(date +%F)
```

升级前停止服务并备份 `data/`。替换 `nanoops-server` 时保持所有者
`root:nanoops`、权限 `0750`，然后启动服务。发布包默认关闭应用内自更新。
