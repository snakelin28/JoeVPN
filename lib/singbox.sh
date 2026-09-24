#!/usr/bin/env bash
# lib/singbox.sh — sing-box 安装/升级、systemd、服务端配置渲染

SB_SERVICE="/etc/systemd/system/sing-box.service"
GH_API="https://api.github.com/repos/SagerNet/sing-box/releases/latest"

# 取目标版本（去掉前导 v）：
#   config.conf 里 SB_VERSION 非空 → 用固定版本
#   否则先查 GitHub API；API 被限流（AWS 共享 IP 常见，未认证 60 次/小时）
#   再退回读 releases/latest 的跳转地址，不走 API
_latest_version() {
    if [[ -n "${SB_VERSION:-}" ]]; then echo "${SB_VERSION#v}"; return; fi
    local v
    v="$(curl -fsSL --max-time 10 "${GH_API}" 2>/dev/null | jq -r '.tag_name // empty' 2>/dev/null || true)"
    if [[ -z "${v}" ]]; then
        v="$(curl -fsSLI -o /dev/null -w '%{url_effective}' --max-time 10 \
              https://github.com/SagerNet/sing-box/releases/latest 2>/dev/null || true)"
        v="${v##*/}"
    fi
    v="${v#v}"
    [[ "${v}" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]] && echo "${v}" || true
}

# 当前已安装版本（未装则空）
_installed_version() {
    [[ -x "${SB_BIN}" ]] || { echo ""; return; }
    "${SB_BIN}" version 2>/dev/null | awk '/version/ {print $3; exit}' || true
}

install_singbox() {
    local want cur url tmp
    want="$(_latest_version)"
    if [[ -z "${want}" ]]; then
        log_err "无法从 GitHub 获取 sing-box 版本号（网络/限流？）。可在 config.conf 填 SB_VERSION 固定版本后重跑"
        exit 1
    fi
    cur="$(_installed_version)"
    if [[ "${cur}" == "${want}" ]]; then
        log_ok "sing-box 已是最新 ${cur}，跳过下载"
        _ensure_service
        return 0
    fi

    log_info "安装 sing-box ${want}（当前: ${cur:-未安装}）"
    tmp="$(mktemp -d)"
    url="https://github.com/SagerNet/sing-box/releases/download/v${want}/sing-box-${want}-linux-${SB_ARCH}.tar.gz"

    if ! curl -fsSL "${url}" -o "${tmp}/sb.tar.gz"; then
        log_err "下载失败: ${url}"
        rm -rf "${tmp}"; exit 1
    fi
    tar -xzf "${tmp}/sb.tar.gz" -C "${tmp}"
    install -m 0755 "${tmp}/sing-box-${want}-linux-${SB_ARCH}/sing-box" "${SB_BIN}"
    rm -rf "${tmp}"
    log_ok "sing-box ${want} 已安装 -> ${SB_BIN}"

    _ensure_dirs
    _ensure_service
}

_ensure_dirs() {
    mkdir -p "${SB_CONFIG_DIR}" "${SB_CERT_DIR}" "${SB_DATA_DIR}"
}

_ensure_service() {
    if [[ -f "${SB_SERVICE}" ]]; then return 0; fi
    log_info "写入 systemd 服务单元"
    cat > "${SB_SERVICE}" <<EOF
[Unit]
Description=sing-box service (JoeVPN)
Documentation=https://sing-box.sagernet.org
After=network.target nss-lookup.target network-online.target

[Service]
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
ExecStart=${SB_BIN} -D ${SB_DATA_DIR} -C ${SB_CONFIG_DIR} run
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=10
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
}

# 渲染服务端 config.json（依赖已生成的凭据变量）
render_server_config() {
    local cfg="${SB_CONFIG_DIR}/config.json"
    log_info "生成服务端配置 -> ${cfg}"

    # Hy2 带宽片段：自适应 vs 固定
    local hy2_bw
    if [[ "${HY2_BANDWIDTH_MODE}" == "adaptive" ]]; then
        hy2_bw='      "ignore_client_bandwidth": true,'
    else
        hy2_bw="      \"up_mbps\": ${HY2_UP_MBPS},
      \"down_mbps\": ${HY2_DOWN_MBPS},"
    fi

    ( umask 077; : > "${cfg}" )   # 含 Reality 私钥和 Hy2 密码，只给 root 读
    cat > "${cfg}" <<EOF
{
  "log": { "level": "info", "timestamp": true },
  "dns": {
    "servers": [
      { "type": "tls", "tag": "google",     "server": "8.8.8.8" },
      { "type": "tls", "tag": "cloudflare", "server": "1.1.1.1" }
    ],
    "strategy": "ipv4_only",
    "final": "google"
  },
  "inbounds": [
    {
      "type": "hysteria2",
      "tag": "hy2-in",
      "listen": "::",
      "listen_port": ${HY2_PORT},
${hy2_bw}
      "users": [
        { "name": "joe", "password": "${HY2_PASSWORD}" }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${HY2_SNI}",
        "certificate_path": "${SB_CERT_DIR}/server.crt",
        "key_path": "${SB_CERT_DIR}/server.key"
      }
    },
    {
      "type": "vless",
      "tag": "reality-in",
      "listen": "::",
      "listen_port": ${REALITY_PORT},
      "users": [
        { "uuid": "${UUID}", "flow": "xtls-rprx-vision" }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${REALITY_SNI}",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "${REALITY_HANDSHAKE_SERVER}",
            "server_port": ${REALITY_HANDSHAKE_PORT}
          },
          "private_key": "${REALITY_PRIVATE_KEY}",
          "short_id": [ "${REALITY_SHORT_ID}" ]
        }
      }
    }
  ],
  "outbounds": [
    { "type": "direct", "tag": "direct" }
  ],
  "route": {
    "default_domain_resolver": "google"
  }
}
EOF
}

check_config() {
    log_info "校验配置语法…"
    if "${SB_BIN}" check -C "${SB_CONFIG_DIR}" 2>/tmp/sb_check.err; then
        log_ok "配置语法通过"
    else
        log_err "配置校验失败："
        cat /tmp/sb_check.err
        exit 1
    fi
}

enable_start() {
    systemctl enable sing-box >/dev/null 2>&1
    systemctl restart sing-box
    sleep 1
    if systemctl is-active --quiet sing-box; then
        log_ok "sing-box 运行中 (active)"
    else
        log_err "sing-box 启动失败，查看： journalctl -u sing-box -n 30 --no-pager"
        exit 1
    fi
}
