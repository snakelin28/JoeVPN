# Joe's Lightsail Installer v1.1 (JoeVPN)

一键在 Lightsail / 任意 Ubuntu·Debian VPS 上部署 **Hysteria2 + VLESS Reality**，
自带 BBR、IPv4/IPv6 转发、QUIC/TCP 缓冲优化、按内存自适应，并自动生成客户端配置。

针对 **Apple TV+ / Netflix / Disney+ / YouTube** 这类长时间、高码率、持续
UDP/TCP 流量做了内核层优化。

## 一键安装（Lightsail 网页 SSH）

1. 新建实例（Ubuntu 22.04/24.04）→ **立刻绑 Static IP**
2. Networking → IPv4 Firewall 放行：TCP 443 / UDP 8443 / TCP 6060
3. 实例页点 **Connect using SSH**，粘这一行：

```bash
curl -fsSL https://github.com/snakelin28/JoeVPN/archive/refs/heads/main.tar.gz | tar xz && cd JoeVPN-main && sudo bash install.sh
```

4. 终端里出现订阅二维码 → 小飞机扫码。扫不出就复制上面两条 vless:// / hysteria2:// 裸链接。
5. `sudo bash backup.sh`，把打印出来的凭据几行存进密码管理器。

实例刚建好就跑也没关系：脚本会先等开机初始化（apt 锁）结束再装。
网页 SSH 中途断了：重新连上，`cd JoeVPN-main && sudo bash install.sh` 再跑一次即可，
凭据会复用，不会重新生成。

## 换 VPS（复用同一套节点，客户端只需重新扫码/换 IP）

新机器上先下载、**先不装**：

```bash
curl -fsSL https://github.com/<你的GitHub用户名>/JoeVPN/archive/refs/heads/main.tar.gz | tar xz && cd JoeVPN-main
nano config.conf      # 把密码管理器里存的 UUID / REALITY_* / HY2_PASSWORD / SUB_TOKEN 填回去
sudo bash install.sh
```

> 想换全新凭据：什么都不填直接装。

## ⚠ 仓库是公开的

- 仓库里的 `config.conf` 凭据字段**永远保持为空**。
- 服务器上跑完后的 `config.conf` 已写入凭据，**不要**从服务器往 GitHub 推任何东西。
- 改脚本只在本地干净副本里改，再上传到 GitHub。

## 目录

| 文件/目录 | 作用 |
|---|---|
| `install.sh` | 一键安装（编排全流程） |
| `update.sh` | 只升级 sing-box 内核 |
| `uninstall.sh` | 卸载 |
| `backup.sh` | 打包配置+证书+凭据 |
| `restore.sh` | 从备份恢复 |
| `config.conf` | 所有可配置参数 + 凭据 |
| `lib/` | 各功能模块 |
| `templates/` | 服务端/客户端配置模板 |
| `clients/` | 生成的客户端配置输出 |

## 内存自适应

脚本按总内存自动分档：

| 档位 | 内存 | 处理 |
|---|---|---|
| small | <1GB (512MB) | QUIC/TCP 缓冲上限 16MB，自动建 2G swap，低 swappiness |
| medium | 1–2GB | 缓冲上限 25MB |
| large | 2GB+ | 缓冲上限 32MB |

## 重要提醒（脚本管不到的部分）

- **Lightsail 控制台防火墙**要手动放行 `TCP 443` + `UDP 8443`。
- 给实例绑 **Static IP**，否则重启后公网 IP 变、客户端全失效。
- Clash 端必须用新内核（Clash.Meta / mihomo / Verge Rev / Stash）才认
  hysteria2 / reality。
- 备份文件含全部凭据，存密码管理器或加密盘，别放公开网盘/Gist。

## 自托管订阅服务

安装完自动在 `SUB_PORT`(默认 6060)起一个订阅服务，生成一条 YAML 订阅链接
+ 终端二维码，小飞机/Clash 扫码即可添加订阅。

- 随机 32 位路径防扫描，链接形如 `http://IP:6060/<随机串>/JoeVPN.yaml`
- **Lightsail 控制台防火墙需额外放行 TCP 6060**，否则客户端拉不到订阅
- 换 VPS / 公网 IP 变了，订阅链接会变，需重新导入
- 链接含凭据，别外传、别贴公开处

> 若小飞机(Shadowrocket)对 YAML 订阅兼容不佳，可改用 base64 的 sub.txt；
> 裸链接(links.txt)始终可本地导入，不依赖订阅服务。
