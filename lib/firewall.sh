#!/usr/bin/env bash
# lib/firewall.sh — 主机防火墙（ufw）。注意：Lightsail 还有「控制台防火墙」需手动开！

configure_firewall() {
    if ! command -v ufw >/dev/null 2>&1; then
        log_info "未检测到 ufw，跳过主机防火墙（Lightsail 主要靠控制台防火墙）"
        return 0
    fi

    # 探测当前 SSH 端口，避免开 ufw 把自己关在门外
    local ssh_port
    ssh_port="$(ss -tlnp 2>/dev/null | awk '/sshd/{split($4,a,":"); print a[length(a)]; exit}')"
    ssh_port="${ssh_port:-22}"

    log_info "配置 ufw：放行 SSH:${ssh_port}/tcp, Reality:${REALITY_PORT}/tcp, Hy2:${HY2_PORT}/udp"
    ufw allow "${ssh_port}/tcp"        >/dev/null 2>&1 || true
    ufw allow "${REALITY_PORT}/tcp"    >/dev/null 2>&1 || true
    ufw allow "${HY2_PORT}/udp"        >/dev/null 2>&1 || true
    ufw --force enable                 >/dev/null 2>&1 || true
    log_ok "ufw 就绪"
}

lightsail_reminder() {
    cat <<EOF

${C_YEL}‼ Lightsail 控制台防火墙必须手动开（脚本改不到 AWS）：${C_RST}
   控制台 → 实例 → Networking → IPv4 Firewall，添加：
     • Custom / TCP / ${REALITY_PORT}
     • Custom / UDP / ${HY2_PORT}
     • Custom / TCP / ${SUB_PORT}   (订阅服务)
   另外确认已绑 Static IP，否则重启后公网 IP 会变、所有客户端配置失效。
EOF
}
