#!/bin/bash
# SN6140 扬声器修复看护进程
#   默认: 每 2 秒检查一次 codec 状态，发现驱动重新静音/改路由就重新注入 verb
#   --once: 注入一次后退出（供 system-sleep 休眠恢复钩子使用）
# 安装位置: /usr/local/sbin/sn6140-watchdog

D=/dev/snd/hwC0D0

wait_dev() {
    for i in $(seq 1 120); do
        [ -e "$D" ] && return 0
        sleep 0.5
    done
    return 1
}

unmute_ch() {
    # 读当前增益（0xb00 左 / 0xb01 右），只清静音位，不改变增益值
    local verb=$1 setverb=$2
    local v
    v=$(hda-verb "$D" 0x10 "$verb" 0x0 2>/dev/null | tail -1 | awk '{print $3}')
    [ -n "$v" ] || return
    v=$(( v & 0x7f ))
    hda-verb "$D" 0x10 "$setverb" "$v" >/dev/null
}

apply() {
    hda-verb "$D" 0x16 0x701 0x00 >/dev/null   # 耳机引脚 0x16 -> DAC 0x10
    hda-verb "$D" 0x17 0x701 0x00 >/dev/null   # 扬声器引脚 0x17 -> DAC 0x10
    hda-verb "$D" 0x17 0x70C 0x02 >/dev/null   # 扬声器 EAPD 使能
    unmute_ch 0xB00 0x3B0                     # DAC 0x10 左声道仅解除静音
    unmute_ch 0xB01 0x3B1                     # DAC 0x10 右声道仅解除静音
}

needs_fix() {
    local c
    c=$(cat /proc/asound/card0/codec#0 2>/dev/null) || return 1
    # 1) DAC 0x10 被静音（Amp-Out vals 含 0x80）
    echo "$c" | grep -A9 "^Node 0x10 " | grep -q "0x80" && return 0
    # 2) 耳机引脚 0x16 不再指向 DAC 0x10
    echo "$c" | grep -A13 "^Node 0x16 " | grep -qE "0x10\*" || return 0
    # 3) 扬声器引脚 0x17 不再指向 DAC 0x10
    echo "$c" | grep -A13 "^Node 0x17 " | grep -qE "0x10\*" || return 0
    return 1
}

wait_dev || { echo "SN6140: hwdep device not found" >&2; exit 1; }

if [ "$1" = "--once" ]; then
    apply
    exit 0
fi

while true; do
    if needs_fix; then
        apply
    fi
    sleep 2
done
