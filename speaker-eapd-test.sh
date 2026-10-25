#!/bin/bash
# SN6140 扬声器功放 EAPD 测试（临时修改，重启后失效）
# 用法: sudo bash speaker-eapd-test.sh
set -e

echo "==> 当前扬声器引脚 0x17 状态:"
grep -A11 "Node 0x17" /proc/asound/card0/codec#0 | grep "Pin-ctls"

echo "==> 用 EAPD/BTL 使能扬声器功放 (verb 0x70C, 值 0x02)..."
hda-verb /dev/snd/hwC0D0 0x17 0x70C 0x0002

echo "==> 播放 3 段 440Hz 测试音（约 8 秒），请听扬声器是否有声音..."
speaker-test -D pipewire -c 2 -t sine -f 440 -l 3 2>/dev/null

echo "==> 测试结束。听到声音了吗？"
