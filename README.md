# Singbox 一键部署 / One-Click Deploy

> [中文](#中文) | [English](#english)

---

## 中文

在 Linux 服务器上一键部署 sing-box + Reality + Nginx 订阅服务的 Bash 脚本。自动完成安装、密钥生成、服务端配置、端口放行与订阅文件生成，开箱即用。

## 特性

- 自动安装 sing-box 并生成 UUID / Reality 密钥对 / ShortID
- 启用 VLESS + Reality 服务端配置，默认监听 443
- 自动配置 systemd 服务与防火墙规则
- 通过 Nginx 暴露通用订阅（base64）与 Clash / Mihomo 订阅（YAML）
- 幂等设计：已安装内容跳过、已生成密钥复用，可重复执行
- 默认不在终端打印敏感信息，写入受保护文件，便于安全查看

## 环境要求

- Debian / Ubuntu 服务器
- root 或 sudo 权限
- 可访问互联网

## 快速开始

```bash
git clone https://github.com/YonghengZou/Singbox-Deploy.git
cd Singbox-Deploy
chmod +x deploy_singbox_full.sh
sudo ./deploy_singbox_full.sh
```

如需在终端查看完整部署细节：

```bash
SHOW_SECRETS=1 sudo ./deploy_singbox_full.sh
```

自定义端口或伪装域名：

```bash
LISTEN_PORT=443 SUB_PORT=8443 REALITY_SNI=example.com sudo ./deploy_singbox_full.sh
```

## 默认端口

| 端口 | 用途 |
| --- | --- |
| 443 | sing-box 监听端口 |
| 8443 | 订阅文件访问端口 |

`REALITY_SNI` 默认使用 `swdist.apple.com`，可在脚本中或通过环境变量替换为其他更合适的伪装域名。

## 部署结果

脚本执行完成后会输出：

- 服务器 IP、UUID、PublicKey、ShortID
- VLESS 链接
- 通用订阅链接（V2Box / v2rayNG / NekoBox）
- Clash 专用订阅链接（Mihomo 内核）

## 注意事项

- **云平台防火墙**：除服务器内部防火墙外，还需在云平台安全组 / NSG 放行对应端口。
- **订阅链接安全**：链接中包含敏感信息，请勿随意分享。
- **可重复执行**：脚本幂等，已安装内容跳过、已生成密钥复用，适合多次运行与维护。

## 文件

- [`deploy_singbox_full.sh`](deploy_singbox_full.sh) — 完整部署脚本
- [`LICENSE`](LICENSE) — 项目许可证

---

## English

A Bash script to deploy a sing-box + Reality + Nginx subscription service on a Linux server in one click. It automatically handles installation, key generation, server-side configuration, port opening, and subscription file generation — ready to use out of the box.

## Features

- Auto-install sing-box and generate UUID / Reality keypair / ShortID
- Enable VLESS + Reality server config, listening on 443 by default
- Configure systemd service and firewall rules automatically
- Expose generic subscription (base64) and Clash / Mihomo subscription (YAML) via Nginx
- Idempotent: skips installed parts, reuses generated keys, safe to re-run
- Sensitive info is not printed to the terminal by default; written to protected files for secure review

## Requirements

- Debian / Ubuntu server
- root or sudo privileges
- Internet access

## Quick Start

```bash
git clone https://github.com/YonghengZou/Singbox-Deploy.git
cd Singbox-Deploy
chmod +x deploy_singbox_full.sh
sudo ./deploy_singbox_full.sh
```

To view full deployment details in the terminal:

```bash
SHOW_SECRETS=1 sudo ./deploy_singbox_full.sh
```

Customize port or SNI:

```bash
LISTEN_PORT=443 SUB_PORT=8443 REALITY_SNI=example.com sudo ./deploy_singbox_full.sh
```

## Default Ports

| Port | Usage |
| --- | --- |
| 443 | sing-box listen port |
| 8443 | subscription file access port |

`REALITY_SNI` defaults to `swdist.apple.com`; replace it with a more suitable camouflage domain in the script or via environment variable.

## Deployment Output

After the script finishes, it prints:

- Server IP, UUID, PublicKey, ShortID
- VLESS link
- Generic subscription link (V2Box / v2rayNG / NekoBox)
- Clash-specific subscription link (Mihomo core)

## Notes

- **Cloud firewall**: In addition to the in-server firewall, open the corresponding ports in your cloud provider's security group / NSG.
- **Subscription link security**: Links contain sensitive info — do not share them casually.
- **Re-runnable**: The script is idempotent — installed parts are skipped, generated keys are reused, suitable for repeated runs and maintenance.

## Files

- [`deploy_singbox_full.sh`](deploy_singbox_full.sh) — full deployment script
- [`LICENSE`](LICENSE) — project license
