#!/bin/bash
# SN6140 扬声器路由诊断实验 v2（全部临时，重启后失效）
# 用法: sudo bash speaker-route-test2.sh
# 4 段八度相隔的测试音（220/440/880/1760 Hz），请记住第几段有声音
D=/dev/snd/hwC0D0

dump() {
  grep -A9 "Node 0x1[067]" /proc/asound/card0/codec#0 \
    | grep -E "Node|Amp-Out vals|Converter|Pin-ctls|Connection:" > "$1"
}

tone() {
  echo ""
  echo ">>> 【第$2段】播放 $1 Hz 测试音（约10秒）——请听扬声器！"
  speaker-test -D pipewire -c 2 -t sine -f $1 -l 4 2>/dev/null
  echo "<<< 第$2段结束"
  sleep 2
}

echo "========== 阶段1: 社区路由 + EAPD + GPIO =========="
hda-verb $D 0x16 0x701 0x01 >/dev/null
hda-verb $D 0x17 0x70C 0x02 >/dev/null
hda-verb $D 0x01 0x715 0x02 >/dev/null
dump /tmp/route-test-phase1.txt
tone 220 1

echo "========== 阶段2: 解除 DAC 0x10 静音 =========="
hda-verb $D 0x10 0x3B0 0x4A >/dev/null
hda-verb $D 0x10 0x3B1 0x4A >/dev/null
dump /tmp/route-test-phase2.txt
tone 440 2

echo "========== 阶段3: 扬声器引脚 0x17 改接 DAC 0x10 =========="
hda-verb $D 0x17 0x701 0x00 >/dev/null
dump /tmp/route-test-phase3.txt
tone 880 3

echo "========== 阶段4: 耳机引脚 0x16 接回 0x10 + GPIO 归零 =========="
hda-verb $D 0x16 0x701 0x00 >/dev/null
hda-verb $D 0x01 0x715 0x00 >/dev/null
dump /tmp/route-test-phase4.txt
tone 1760 4

echo "========== 完成 =========="
echo "请告诉 Claude：第 1 / 2 / 3 / 4 段中，哪几段听到了声音？"
