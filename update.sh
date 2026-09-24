#!/usr/bin/env bash
# update.sh — 只升级 sing-box 内核到最新版，保留现有配置
set -Eeuo pipefail
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_FILE="${PROJECT_DIR}/config.conf"
source "${PROJECT_DIR}/lib/common.sh"
source "${CONF_FILE}"
source "${PROJECT_DIR}/lib/system.sh"
source "${PROJECT_DIR}/lib/singbox.sh"

check_root
detect_arch

log_info "检查 sing-box 更新…"
install_singbox         # 内含「已是最新则跳过」逻辑

log_info "重启服务应用新内核"
systemctl restart sing-box
sleep 1
if systemctl is-active --quiet sing-box; then
    log_ok "更新完成，sing-box 运行中：$("${SB_BIN}" version | awk '/version/{print $3}')"
else
    log_err "重启后未运行，查看： journalctl -u sing-box -n 30 --no-pager"
    exit 1
fi
