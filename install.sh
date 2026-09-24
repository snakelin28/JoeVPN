#!/usr/bin/env bash
# ============================================================
#  Joe's Lightsail Installer v1.2  —  install.sh
#  一键：更新系统 + 装 sing-box + BBR + 转发 + 内存自适应
#         + Hysteria2 + Reality + systemd + 客户端配置
#  流媒体优化：Apple TV+ / Netflix / Disney+ / YouTube
# ============================================================
set -Eeuo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_FILE="${PROJECT_DIR}/config.conf"

# --- 载入库 ---
# shellcheck source=lib/common.sh
source "${PROJECT_DIR}/lib/common.sh"

if [[ ! -f "${CONF_FILE}" ]]; then
    log_err "找不到 config.conf"; exit 1
fi
# shellcheck source=config.conf
source "${CONF_FILE}"

for m in system optimize singbox reality hy2 firewall client subserver; do
    # shellcheck disable=SC1090
    source "${PROJECT_DIR}/lib/${m}.sh"
done

trap 'log_err "在第 ${LINENO} 行出错，安装中断"; exit 1' ERR

main() {
    echo "${C_GRN}"
    echo "   ╔══════════════════════════════════════════╗"
    echo "   ║      Joe's Lightsail Installer  v1.2      ║"
    echo "   ╚══════════════════════════════════════════╝"
    echo "${C_RST}"

    # 1. 环境
    check_root
    detect_os
    detect_arch
    detect_ram

    # 2. 系统 & 依赖
    update_system
    install_deps
    detect_public_ip

    # 3. sing-box 本体
    install_singbox

    # 4. 凭据 & 证书（留空则自动生成并写回 config.conf）
    gen_reality
    gen_hy2

    # 5. 渲染服务端配置 + 校验
    render_server_config
    check_config

    # 6. 系统优化（BBR / 转发 / QUIC-TCP 缓冲 / 内存自适应 / swap）
    optimize_all

    # 7. 防火墙
    configure_firewall

    # 8. 启动
    enable_start

    # 9. 客户端配置
    generate_clients

    # 10. 自托管订阅服务（生成链接 + 二维码）
    setup_subscription

    # 11. 总结 + 提醒 + 订阅二维码
    print_summary
    lightsail_reminder
    print_subscription

    log_ok "全部完成。建议接着跑： bash backup.sh"
}

main "$@"
