#!/bin/bash
# SN6140 扬声器路由诊断实验（全部临时，重启后失效）
# 用法: sudo bash speaker-route-test.sh
# 会依次播放 4 段不同频率的测试音，请记住哪几段听到了声音
D=/dev/snd/hwC0D0

dump() {
  echo "--- 关键节点状态:"
  grep -A9 "Node 0x1[067]" /proc/asound/card0/codec#0 \
    | grep -E "Node|Amp-Out vals|Converter|Pin-ctls|Connection:"
  echo "--- DAC 0x10/0x11:"
  grep -A4 "Node 0x1[01] " /proc/asound/card0/codec#0 \
    | grep -E "Node|Amp-Out vals|Converter"
}

tone() { echo ">>> 播放 $1 Hz 测试音（约5秒）..."; speaker-test -D pipewire -c 2 -t sine -f $1 -l 2 2>/dev/null; }

echo "========== 阶段1: 社区方案——耳机引脚改接扬声器DAC + EAPD + GPIO =========="
hda-verb $D 0x16 0x701 0x01   # 耳机引脚 0x16 连接选择 -> 0x11（扬声器DAC）
hda-verb $D 0x17 0x70C 0x02   # 扬声器 EAPD 使能
hda-verb $D 0x01 0x715 0x02   # GPIO 数据（关闭耳机路径）
dump
tone 440

echo "========== 阶段2: 解除 DAC 0x10 静音（0x80 -> 0x4a 满音量）=========="
hda-verb $D 0x10 0x3B0 0x4A   # 左声道 amp: 取消静音, 0dB
hda-verb $D 0x10 0x3B1 0x4A   # 右声道 amp: 取消静音, 0dB
dump
tone 554

echo "========== 阶段3: 强制扬声器引脚 0x17 改接 DAC 0x10 =========="
hda-verb $D 0x17 0x701 0x00
dump
tone 659

echo "========== 阶段4: 耳机引脚 0x16 也接回 DAC 0x10，GPIO 数据置 0 =========="
hda-verb $D 0x16 0x701 0x00
hda-verb $D 0x01 0x715 0x00
dump
tone 880

echo "========== 实验完成 =========="
echo "请告诉 Claude：440 / 554 / 659 / 880 Hz 中，哪几段听到了声音？"
