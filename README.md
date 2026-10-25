# sn6140-kernel-patch

华为 MateBook 14(SN6140 codec,PCI SSID `19e5:329e`)在 Linux 下内置扬声器无声问题的内核修复。

## 状态

- **上游**:`0001-ALSA-hda-conexant-Fix-silent-speaker-on-Huawei-MateB.patch` 已于
  2026-09-19 被 Takashi Iwai 合入 sound 子系统 for-next 分支("Applied to for-next
  branch now. Thanks."),将随下一内核合并窗口进入主线。
- **本地**:Ubuntu 26.04(内核 7.0.0-30/31)在发行版内核包含该 quirk 之前,通过
  自编译模块 + 看护进程双保险维持修复(开机/休眠恢复由模块保证,耳机插拔由看护进程兜底)。

## 内容

| 路径 | 说明 |
|---|---|
| `0001-ALSA-hda-conexant-Fix-silent-speaker-on-Huawei-MateB.patch` | 上游提交的 quirk patch(v2) |
| `SUBMISSION.md` | 上游提交记录、发送方式与审查预案 |
| `install-sn6140-fix.sh` | 本地修复安装:看护进程 + 休眠恢复钩子 |
| `sn6140-watchdog.service` / `sn6140-watchdog.sh` | 看护进程(插拔兜底,只清静音位不动增益) |
| `speaker-*.sh` | 排障/验证脚本(EAPD、路由等) |
| `modprobe.d/sn6140-conexant-first.conf` | 模块绑定顺序钩子(conexant 先于 snd-hda-intel 注册),安装到 `/etc/modprobe.d/` |
| `docs/` | 设计文档与实现计划(根因分析、测试协议、模块编译经验) |

## 本地安装(模块已自编译时)

```bash
sudo bash install-sn6140-fix.sh
sudo cp modprobe.d/sn6140-conexant-first.conf /etc/modprobe.d/
```

自编译模块的构建步骤见 `docs/2026-08-30-sn6140-kernel-patch.md`。

## 根因摘要

SN6140 硬件怪癖:扬声器引脚 0x17 的信号源跟随耳机引脚 0x16 的连接选择。generic
解析器在未插耳机时把共享 DAC 0x10 静音,且 EAPD 未使能,导致扬声器无声。修复通过
SSID quirk 抑制 auto-mute、将扬声器引脚固定路由到 DAC 0x10、移除该 DAC 的静音开关,
并在 INIT 时使能 EAPD。详见 `docs/2026-08-30-sn6140-matebook14-audio-fix-design.md`。
