#!/usr/bin/env bash
# lib/optimize.sh — 内核/网络/内存优化
# 针对：长时间、高码率、持续 UDP(QUIC/Hy2) + TCP(Reality) 流媒体
# 目标应用：Apple TV+ / Netflix / Disney+ / YouTube

SYSCTL_FILE="/etc/sysctl.d/99-joevpn.conf"
LIMITS_FILE="/etc/security/limits.d/99-joevpn.conf"

# 根据内存档位给 QUIC/TCP 缓冲上限（单位字节）。都是「上限」不是预分配，小内存也安全。
_buffer_max() {
    case "${RAM_TIER}" in
        small)  echo 16777216  ;;   # 16MB
        medium) echo 26214400  ;;   # 25MB
        large)  echo 33554432  ;;   # 32MB
        *)      echo 16777216  ;;
    esac
}

apply_sysctl() {
    log_info "写入内核网络优化 -> ${SYSCTL_FILE}"
    local bmax
    bmax="$(_buffer_max)"

    {
        echo "# ===== JoeVPN 自动生成，勿手改（改 config.conf 后重跑 install.sh）====="
        echo

        if [[ "${ENABLE_BBR}" == "1" ]]; then
            echo "# --- BBR 拥塞控制：治跨境丢包链路，Reality/TCP 提速最明显 ---"
            echo "net.core.default_qdisc = fq"
            echo "net.ipv4.tcp_congestion_control = bbr"
            echo
        fi

        if [[ "${ENABLE_IP_FORWARD}" == "1" ]]; then
            echo "# --- 转发 ---"
            echo "net.ipv4.ip_forward = 1"
            echo "net.ipv6.conf.all.forwarding = 1"
            echo
        fi

        if [[ "${ENABLE_NET_TUNE}" == "1" ]]; then
            echo "# --- QUIC/Hysteria2(UDP) 缓冲：高码率吞吐关键，缓冲太小会丢包转圈 ---"
            echo "net.core.rmem_max = ${bmax}"
            echo "net.core.wmem_max = ${bmax}"
            echo "net.core.rmem_default = 1048576"
            echo "net.core.wmem_default = 1048576"
            echo "net.core.netdev_max_backlog = 16384"
            echo "net.core.somaxconn = 8192"
            echo
            echo "# --- TCP(Reality) 长连接 & 流媒体优化 ---"
            echo "net.ipv4.tcp_rmem = 4096 87380 ${bmax}"
            echo "net.ipv4.tcp_wmem = 4096 65536 ${bmax}"
            echo "net.ipv4.tcp_mtu_probing = 1          # 跨境 MTU 黑洞探测，防握手卡死"
            echo "net.ipv4.tcp_fastopen = 3"
            echo "net.ipv4.tcp_slow_start_after_idle = 0  # 缓冲/暂停后不重回慢启动，恢复更快"
            echo "net.ipv4.tcp_notsent_lowat = 16384"
            echo "net.ipv4.tcp_fin_timeout = 15"
            echo "net.ipv4.tcp_max_syn_backlog = 8192"
            echo "net.ipv4.udp_rmem_min = 8192"
            echo "net.ipv4.udp_wmem_min = 8192"
            echo
        fi

        if [[ "${ENABLE_MEM_TUNE}" == "1" ]]; then
            echo "# --- 内存策略（按档位 ${RAM_TIER}）---"
            if [[ "${RAM_TIER}" == "small" ]]; then
                echo "vm.swappiness = 10"
                echo "vm.vfs_cache_pressure = 50"
            else
                echo "vm.swappiness = 20"
            fi
            echo
        fi
    } > "${SYSCTL_FILE}"

    sysctl --system >/dev/null 2>&1 || sysctl -p "${SYSCTL_FILE}" >/dev/null 2>&1 || true

    # 校验 BBR 是否真的生效
    if [[ "${ENABLE_BBR}" == "1" ]]; then
        local cc
        cc="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo '?')"
        if [[ "${cc}" == "bbr" ]]; then
            log_ok "BBR 已生效"
        else
            log_warn "BBR 当前为 ${cc}（内核可能不支持，通常 Lightsail Ubuntu 都支持，可忽略或升级内核）"
        fi
    fi
}

apply_limits() {
    log_info "放开文件描述符上限 -> ${LIMITS_FILE}"
    cat > "${LIMITS_FILE}" <<'EOF'
# JoeVPN
* soft nofile 1048576
* hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
EOF
}

# 小内存自动建 swap，避免 apt/编译/突发连接时 OOM
setup_swap() {
    [[ "${ENABLE_MEM_TUNE}" == "1" ]] || return 0
    [[ "${RAM_TIER}" == "small" ]]    || return 0

    if swapon --show 2>/dev/null | grep -q .; then
        log_info "已存在 swap，跳过创建"
        return 0
    fi

    local size="2G" file="/swapfile"
    log_info "小内存机型：创建 ${size} swap"
    if fallocate -l "${size}" "${file}" 2>/dev/null || \
       dd if=/dev/zero of="${file}" bs=1M count=2048 status=none; then
        chmod 600 "${file}"
        mkswap "${file}" >/dev/null
        swapon "${file}"
        grep -q "^${file} " /etc/fstab || echo "${file} none swap sw 0 0" >> /etc/fstab
        log_ok "swap 就绪"
    else
        log_warn "swap 创建失败（磁盘空间不足？），跳过"
    fi
}

optimize_all() {
    apply_sysctl
    apply_limits
    setup_swap
}
