#!/bin/bash
# SN6140 扬声器修复 verb 注入（临时，重启后失效）
# 用法: sudo bash speaker-fix-apply.sh
# 在 Claude 播放测试音期间运行本脚本
D=/dev/snd/hwC0D0
echo "==> 耳机引脚 0x16 改接 DAC 0x10"
hda-verb $D 0x16 0x701 0x00
echo "==> 扬声器引脚 0x17 改接 DAC 0x10"
hda-verb $D 0x17 0x701 0x00
echo "==> 扬声器 EAPD 使能"
hda-verb $D 0x17 0x70C 0x02
echo "==> 确保 DAC 0x10 左右声道未静音、满音量"
hda-verb $D 0x10 0x3B0 0x4A
hda-verb $D 0x10 0x3B1 0x4A
echo "==> 完成。扬声器有声音了吗？"
