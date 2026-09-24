#!/usr/bin/env bash
# restore.sh — 从 backup.sh 生成的 tar.gz 恢复配置
# 用法: sudo bash restore.sh /path/to/joevpn-backup-YYYYMMDD-HHMMSS.tar.gz
set -Eeuo pipefail
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_FILE="${PROJECT_DIR}/config.conf"
source "${PROJECT_DIR}/lib/common.sh"
source "${CONF_FILE}"

[[ ${EUID} -eq 0 ]] || { log_err "请用 root 运行"; exit 1; }

BK="${1:-}"
if [[ -z "${BK}" || ! -f "${BK}" ]]; then
    log_err "用法: sudo bash restore.sh <备份文件.tar.gz>"
    exit 1
fi

TMP="$(mktemp -d)"
tar -xzf "${BK}" -C "${TMP}"

log_info "恢复服务端配置与证书 -> ${SB_CONFIG_DIR}"
mkdir -p "${SB_CONFIG_DIR}"
cp -a "${TMP}/etc-sing-box/." "${SB_CONFIG_DIR}/"
chmod 600 "${SB_CONFIG_DIR}/certs/server.key" 2>/dev/null || true

log_info "恢复项目 config.conf 与 clients/"
cp -a "${TMP}/project/config.conf" "${CONF_FILE}"
cp -a "${TMP}/project/clients" "${PROJECT_DIR}/" 2>/dev/null || true
rm -rf "${TMP}"

if [[ -x "${SB_BIN}" ]]; then
    log_info "校验并重启"
    "${SB_BIN}" check -C "${SB_CONFIG_DIR}" && systemctl restart sing-box || true
    systemctl is-active --quiet sing-box && log_ok "已恢复并运行" || \
        log_warn "服务未运行，可能这台还没装 sing-box，先跑 install.sh"
else
    log_warn "本机还没装 sing-box，先跑 install.sh（它会复用恢复出来的 config.conf 凭据）"
fi
