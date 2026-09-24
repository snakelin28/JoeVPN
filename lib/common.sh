#!/usr/bin/env bash
# lib/common.sh — 通用日志/颜色（被其它 lib 依赖，最先 source）

if [[ -t 1 ]]; then
    C_RST=$'\033[0m'; C_GRN=$'\033[0;32m'; C_RED=$'\033[0;31m'
    C_YEL=$'\033[0;33m'; C_BLU=$'\033[0;34m'
else
    C_RST=''; C_GRN=''; C_RED=''; C_YEL=''; C_BLU=''
fi

log_info() { echo "${C_BLU}[*]${C_RST} $*"; }
log_ok()   { echo "${C_GRN}[✓]${C_RST} $*"; }
log_warn() { echo "${C_YEL}[!]${C_RST} $*"; }
log_err()  { echo "${C_RED}[✗]${C_RST} $*" >&2; }
