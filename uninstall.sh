#!/usr/bin/env bash
# uninstall.sh — 卸载 sing-box 及本项目写入的系统文件（不删你的备份/clients）
set -Eeuo pipefail
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_FILE="${PROJECT_DIR}/config.conf"
source "${PROJECT_DIR}/lib/common.sh"
source "${CONF_FILE}"

[[ ${EUID} -eq 0 ]] || { log_err "请用 root 运行"; exit 1; }

read -r -p "确认卸载 sing-box 及优化配置？(y/N) " ans
[[ "${ans}" == "y" || "${ans}" == "Y" ]] || { log_info "已取消"; exit 0; }

log_info "停止并禁用服务"
systemctl stop sing-box 2>/dev/null || true
systemctl disable sing-box 2>/dev/null || true
systemctl stop joevpn-sub 2>/dev/null || true
systemctl disable joevpn-sub 2>/dev/null || true

log_info "删除文件"
rm -f  /etc/systemd/system/sing-box.service
rm -f  /etc/systemd/system/joevpn-sub.service
rm -f  "${SB_BIN}"
rm -rf "${SB_CONFIG_DIR}" "${SB_DATA_DIR}"
rm -rf /var/lib/joevpn-sub
rm -f  /etc/sysctl.d/99-joevpn.conf
rm -f  /etc/security/limits.d/99-joevpn.conf
systemctl daemon-reload
sysctl --system >/dev/null 2>&1 || true

log_warn "swap(/swapfile) 与 ufw 规则未自动删除，如需清理请手动处理。"
log_ok "卸载完成。clients/ 与 backups 保留在项目目录。"
