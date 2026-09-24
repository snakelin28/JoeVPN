#!/usr/bin/env bash
# lib/hy2.sh — 生成 Hysteria2 密码 + 自签证书

gen_hy2() {
    # URL-safe 密码（去掉 + / =，省得放进分享链接还要转义）
    if [[ -z "${HY2_PASSWORD}" ]]; then
        HY2_PASSWORD="$(openssl rand -base64 24 | tr '+/' '-_' | tr -d '=')"
        save_conf_value HY2_PASSWORD "${HY2_PASSWORD}"
        log_info "生成 Hy2 密码"
    fi

    # 自签证书（100 年，免续期）
    local crt="${SB_CERT_DIR}/server.crt"
    local key="${SB_CERT_DIR}/server.key"
    if [[ -f "${crt}" && -f "${key}" ]]; then
        log_info "已存在自签证书，跳过"
        return 0
    fi
    mkdir -p "${SB_CERT_DIR}"
    log_info "生成自签证书 (CN=${HY2_SNI})"
    openssl ecparam -genkey -name prime256v1 -out "${key}" 2>/dev/null
    openssl req -new -x509 -days 36500 -key "${key}" -out "${crt}" \
        -subj "/CN=${HY2_SNI}" 2>/dev/null
    chmod 600 "${key}"
    log_ok "证书就绪"
}
