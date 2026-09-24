#!/usr/bin/env bash
# backup.sh — 打包服务端配置+证书+凭据+客户端配置，生成可下载的 tar.gz
set -Eeuo pipefail
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_FILE="${PROJECT_DIR}/config.conf"
source "${PROJECT_DIR}/lib/common.sh"
source "${CONF_FILE}"

[[ ${EUID} -eq 0 ]] || { log_err "请用 root 运行（需读证书私钥）"; exit 1; }

BACKUP_DIR="${PROJECT_DIR}/backups"
mkdir -p "${BACKUP_DIR}"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="${BACKUP_DIR}/joevpn-backup-${STAMP}.tar.gz"

# 收集要备份的内容到临时目录，保持可直接 restore 的结构
TMP="$(mktemp -d)"
mkdir -p "${TMP}/etc-sing-box" "${TMP}/project"
cp -a "${SB_CONFIG_DIR}/." "${TMP}/etc-sing-box/" 2>/dev/null || true
cp -a "${CONF_FILE}"        "${TMP}/project/config.conf"
cp -a "${PROJECT_DIR}/clients" "${TMP}/project/clients" 2>/dev/null || true

tar -czf "${OUT}" -C "${TMP}" .
rm -rf "${TMP}"
chmod 600 "${OUT}"
# 属主改回 sudo 前的用户（ubuntu），否则 scp 用 ubuntu 登录读不到
[[ -n "${SUDO_USER:-}" ]] && chown "${SUDO_USER}:" "${OUT}" "${BACKUP_DIR}" || true
PUB_IP="$(curl -fsS4 --max-time 6 https://api.ipify.org 2>/dev/null || echo 公网IP)"

log_ok "备份完成: ${OUT}  ($(du -h "${OUT}" | cut -f1))"
cat <<EOF

${C_YEL}【最简单】把下面几行整段复制进密码管理器——换机器复用节点只需要它们：${C_RST}
$(grep -E '^(UUID|REALITY_PRIVATE_KEY|REALITY_PUBLIC_KEY|REALITY_SHORT_ID|HY2_PASSWORD|SUB_TOKEN)=' "${CONF_FILE}" | sed 's/^/  /')

${C_YEL}【完整备份文件】如需拉回本地（在你 Mac 终端执行，需要 .pem）：${C_RST}
  scp -i ~/Downloads/你的密钥.pem ubuntu@${PUB_IP}:${OUT} ~/Desktop/

⚠ 以上含全部凭据，存密码管理器或加密盘，别放公开网盘，更别传回 GitHub。
EOF
