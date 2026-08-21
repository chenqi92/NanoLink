# NanoOps Server 公网部署安全检查

检查日期：2026-08-21。

## 已验证

- Dashboard API 默认要求 JWT/设备令牌；用户、令牌、部署、构建、设置、自更新
  等管理接口要求超级管理员。
- 公开注册默认关闭；首次管理员可通过 root-only 环境文件安全初始化。
- 密码使用 bcrypt；登录对用户名和来源 IP 双重限速；未知用户也执行 bcrypt
  对比，避免明显的用户名计时枚举。
- 浏览器 JWT 只放入 HttpOnly、SameSite=Strict Cookie；HTTPS 下同时设置
  Secure。跨域来源、WebSocket Origin 和转发代理头均按白名单处理。
- 上传、日志、LLM 响应、自更新下载等入口有大小或超时限制；构建 URL 有
  私网/保留地址拦截，降低 SSRF 风险。
- Agent Token 和设备 Token 在数据库中保存哈希；JWT 密钥、管理员密码不会
  写入仓库或普通配置文件。
- `go test ./...`、`go vet ./...`、前端测试和生产构建通过。
- `npm audit --omit=dev` 报告 0 个已知生产依赖漏洞。

## 本次修复

- Go 运行时从 1.26.5 升到 1.26.6，修复官方漏洞扫描识别出的 7 个可达标准库
  漏洞（TLS、HTTP/2、URL、XML、ASN.1/IDNA 等解析路径）。
- SMTP envelope/header 地址改用 `net/mail` 严格解析，阻断换行或 SMTP 参数
  注入。
- SQLite 默认数据目录权限从 `0755` 收紧到 `0750`。
- standalone systemd 单元使用非 root 用户、只允许写入 data、移除全部 Linux
  capabilities，并启用多项 namespace/filesystem/kernel hardening。

## 部署边界与剩余风险

- 服务当前监听所有网卡，必须依靠云安全组/主机防火墙关闭 HTTP、Agent WS、
  gRPC 应用端口；公网只经 nginx 的 443 进入。当前不使用 Agent 时尤其不要
  开放 WS/gRPC。
- 登录限速保存在单进程内存中，不能替代 nginx/WAF 的分布式限速。示例 nginx
  已对登录、注册和配对入口增加第二层 IP 限速。
- 系统没有 MFA。管理员密码应使用密码管理器生成的长随机值，`server.env`
  必须保持 `0600`，并限制 SSH/root 权限。
- 这是一轮源码、依赖、配置和运行烟雾检查，不等同于对真实云主机、nginx、
  DNS/TLS、操作系统补丁和云安全组进行渗透测试。

