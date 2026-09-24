#!/usr/bin/env bash
# lib/system.sh — 系统检测与基础环境
# 依赖 lib/common.sh 里的 log_* 函数

check_root() {
    if [[ ${EUID} -ne 0 ]]; then
        log_err "请用 root 运行： sudo bash install.sh"
        exit 1
    fi
}

detect_os() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        OS_ID="${ID:-unknown}"
        OS_VER="${VERSION_ID:-unknown}"
    else
        log_err "无法识别系统（缺少 /etc/os-release）"
        exit 1
    fi
    case "${OS_ID}" in
        ubuntu|debian) : ;;
        *) log_warn "脚本主要面向 Ubuntu/Debian，当前 ${OS_ID} 未充分测试，继续…" ;;
    esac
    log_info "系统: ${OS_ID} ${OS_VER}"
}

detect_arch() {
    local m
    m="$(uname -m)"
    case "${m}" in
        x86_64|amd64)   SB_ARCH="amd64" ;;
        aarch64|arm64)  SB_ARCH="arm64" ;;
        armv7l|armv7)   SB_ARCH="armv7" ;;
        *) log_err "不支持的架构: ${m}"; exit 1 ;;
    esac
    log_info "架构: ${SB_ARCH}"
}

# 检测总内存(MB)，写入全局 RAM_MB，并归档到内存档位 RAM_TIER
detect_ram() {
    RAM_MB="$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo)"
    if   (( RAM_MB < 1024 )); then RAM_TIER="small"     # ~512MB
    elif (( RAM_MB < 2048 )); then RAM_TIER="medium"    # ~1GB
    else                           RAM_TIER="large"     # 2GB+
    fi
    log_info "内存: ${RAM_MB} MB  (档位: ${RAM_TIER})"
}

# 新实例开机后 cloud-init / unattended-upgrades 会占着 apt 锁几分钟，
# 不等的话 apt-get 直接报 "Could not get lock" 中断安装
APT_OPTS=(-y -q -o DPkg::Lock::Timeout=600
          -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)

wait_for_boot() {
    if command -v cloud-init >/dev/null 2>&1; then
        log_info "等待实例首次开机初始化完成（cloud-init）…"
        cloud-init status --wait >/dev/null 2>&1 || true
    fi
}

update_system() {
    wait_for_boot
    log_info "更新系统软件包…"
    export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a
    apt-get update -q -o DPkg::Lock::Timeout=600
    apt-get upgrade "${APT_OPTS[@]}"
}

install_deps() {
    log_info "安装依赖…"
    export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a
    apt-get install "${APT_OPTS[@]}" \
        curl wget tar jq openssl ca-certificates \
        uuid-runtime iproute2 qrencode python3 >/dev/null
    log_ok "依赖就绪"
}

# 探测公网 IP（多源容错），结果写入全局 PUBLIC_IP
detect_public_ip() {
    local ip url
    for url in https://api.ipify.org https://ipv4.icanhazip.com https://ifconfig.me/ip; do
        # 末尾 || true：否则 set -e + pipefail 下第一个源失败就整个脚本退出，后备源永远轮不到
        ip="$(curl -fsS4 --max-time 6 "${url}" 2>/dev/null | tr -d '[:space:]' || true)"
        if [[ "${ip}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            PUBLIC_IP="${ip}"
            log_info "公网 IP: ${PUBLIC_IP}"
            return 0
        fi
    done
    log_warn "自动探测公网 IP 失败，客户端配置里请手动替换 __PUBLIC_IP__"
    PUBLIC_IP="__PUBLIC_IP__"
    return 0
}
