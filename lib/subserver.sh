#!/usr/bin/env bash
# lib/subserver.sh — 自托管订阅服务
# 在 SUB_PORT 上用极简 HTTP 服务挂 clients/ 目录，随机长路径防扫描。
# 生成一条 YAML 订阅链接 + 终端二维码。

SUB_SERVICE="/etc/systemd/system/joevpn-sub.service"
SUB_ROOT="/var/lib/joevpn-sub"          # 对外暴露的根目录（只放订阅文件）

# 生成/复用随机路径（32 hex），写回 config.conf 以便换 VPS 复用同一路径
_ensure_sub_token() {
    if [[ -z "${SUB_TOKEN:-}" ]]; then
        SUB_TOKEN="$(openssl rand -hex 16)"     # 32 字符
        save_conf_value SUB_TOKEN "${SUB_TOKEN}"
        log_info "生成订阅随机路径: ${SUB_TOKEN}"
    fi
}

# 把订阅文件放到随机子目录，只暴露该目录（别人不知道路径就访问不到）
_publish_files() {
    local dir="${SUB_ROOT}/${SUB_TOKEN}"
    # 清掉旧 token 目录，只保留当前这一个
    rm -rf "${SUB_ROOT}"
    mkdir -p "${dir}"
    # 关键：根目录放空 index.html。否则 python http.server 会对
    # http://IP:6060/ 返回目录列表，直接把随机路径暴露给端口扫描者。
    : > "${SUB_ROOT}/index.html"
    : > "${dir}/index.html"
    # 只发布 YAML（带分流规则）。如需 base64 版可自行加 sub.txt
    cp -f "${PROJECT_DIR}/clients/${CLIENT_NAME}.yaml" "${dir}/${CLIENT_NAME}.yaml"
    find "${SUB_ROOT}" -type d -exec chmod 755 {} +
    find "${SUB_ROOT}" -type f -exec chmod 644 {} +
}

_install_sub_service() {
    # 用 python3 内置 http.server 挂 SUB_ROOT。绑 0.0.0.0:SUB_PORT。
    cat > "${SUB_SERVICE}" <<EOF
[Unit]
Description=JoeVPN subscription server
After=network.target

[Service]
Type=simple
ExecStart=$(command -v python3) -m http.server ${SUB_PORT} --directory ${SUB_ROOT} --bind 0.0.0.0
Restart=on-failure
RestartSec=5
# 不用 root 跑对外服务：临时低权限用户 + 系统只读
DynamicUser=yes
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable joevpn-sub >/dev/null 2>&1
    systemctl restart joevpn-sub
    sleep 1
}

# 主入口：由 install.sh 调用
setup_subscription() {
    [[ "${ENABLE_SUB_SERVER:-1}" == "1" ]] || return 0
    log_info "配置自托管订阅服务 (端口 ${SUB_PORT})…"

    _ensure_sub_token
    _publish_files
    _install_sub_service

    SUB_URL="http://${PUBLIC_IP}:${SUB_PORT}/${SUB_TOKEN}/${CLIENT_NAME}.yaml"
    echo "${SUB_URL}" > "${PROJECT_DIR}/clients/subscribe.txt"

    if systemctl is-active --quiet joevpn-sub; then
        log_ok "订阅服务运行中"
    else
        log_warn "订阅服务未起，查看： journalctl -u joevpn-sub -n 20 --no-pager"
    fi

    # ufw 放行订阅端口（Lightsail 控制台仍需手动开）
    if command -v ufw >/dev/null 2>&1; then
        ufw allow "${SUB_PORT}/tcp" >/dev/null 2>&1 || true
    fi
}

# 打印订阅链接 + 二维码（install.sh 结尾调用）
print_subscription() {
    [[ "${ENABLE_SUB_SERVER:-1}" == "1" ]] || return 0
    [[ -n "${SUB_URL:-}" ]] || return 0

    echo
    echo "${C_GRN}================ 订阅链接（YAML，带分流）================${C_RST}"
    echo "  ${SUB_URL}"
    echo "${C_GRN}=======================================================${C_RST}"

    if command -v qrencode >/dev/null 2>&1; then
        echo
        echo "  扫码导入（小飞机/Clash 扫下面二维码添加订阅）："
        echo
        qrencode -t ANSIUTF8 "${SUB_URL}"
    else
        echo "  (未装 qrencode，无法出二维码；已在依赖里安装，若缺请手动: apt install -y qrencode)"
    fi

    cat <<EOF

${C_YEL}提醒：${C_RST}
  • Lightsail 控制台防火墙还需放行 TCP ${SUB_PORT}（订阅端口）。
  • 换 VPS / 公网 IP 变了，订阅链接会变，需重新导入一次。
  • 此链接含你的节点凭据，别外传、别贴公开处。
  • 所有设备导入完后，建议在 Lightsail 控制台删掉 TCP ${SUB_PORT} 规则
    （或 sudo systemctl stop joevpn-sub）；要再导入时再打开。
EOF
}
