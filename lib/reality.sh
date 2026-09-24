#!/usr/bin/env bash
# lib/reality.sh — 生成 Reality 相关凭据（UUID / 密钥对 / short_id）

# 把 KEY=VALUE 写回 config.conf（存在则替换，不存在则追加）
save_conf_value() {
    local key="$1" val="$2" file="${CONF_FILE}" esc
    chmod 600 "${file}" 2>/dev/null || true   # 写入凭据后不让其他用户读
    esc="$(printf '%s' "${val}" | sed -e 's/[\/&]/\\&/g')"
    if grep -q "^${key}=" "${file}"; then
        sed -i "s/^${key}=.*/${key}=\"${esc}\"/" "${file}"
    else
        echo "${key}=\"${val}\"" >> "${file}"
    fi
}

gen_reality() {
    # UUID
    if [[ -z "${UUID}" ]]; then
        UUID="$(cat /proc/sys/kernel/random/uuid)"
        save_conf_value UUID "${UUID}"
        log_info "生成 UUID: ${UUID}"
    fi

    # Reality 密钥对（私钥+公钥一起产出）
    if [[ -z "${REALITY_PRIVATE_KEY}" || -z "${REALITY_PUBLIC_KEY}" ]]; then
        local out
        out="$("${SB_BIN}" generate reality-keypair 2>/dev/null)"
        REALITY_PRIVATE_KEY="$(awk -F': ' '/PrivateKey/{print $2}' <<<"${out}" | tr -d '[:space:]')"
        REALITY_PUBLIC_KEY="$(awk -F': ' '/PublicKey/{print $2}' <<<"${out}" | tr -d '[:space:]')"
        if [[ -z "${REALITY_PRIVATE_KEY}" || -z "${REALITY_PUBLIC_KEY}" ]]; then
            log_err "Reality 密钥生成失败"
            exit 1
        fi
        save_conf_value REALITY_PRIVATE_KEY "${REALITY_PRIVATE_KEY}"
        save_conf_value REALITY_PUBLIC_KEY  "${REALITY_PUBLIC_KEY}"
        log_info "生成 Reality 密钥对"
    fi

    # short_id：8 字节 = 16 hex
    if [[ -z "${REALITY_SHORT_ID}" ]]; then
        REALITY_SHORT_ID="$(openssl rand -hex 8)"
        save_conf_value REALITY_SHORT_ID "${REALITY_SHORT_ID}"
        log_info "生成 short_id: ${REALITY_SHORT_ID}"
    fi
}
