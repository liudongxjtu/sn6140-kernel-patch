# SN6140 MateBook 14 扬声器修复 — 内核 Patch 设计

日期：2026-08-30
状态：设计已获用户批准（方案 A：机型专属 quirk）

## 1. 背景与问题

Huawei MateBook 14（SSID `0x19e5:0x329e`，Conexant SN6140 codec，vendor ID `0x14f11f87`，
Ubuntu 26.04 LTS，内核 7.0.0-30）内置扬声器在 Linux 下完全无声；USB 耳机正常；Windows 下扬声器正常。

## 2. 根因分析（实测证据）

1. 播放流（stream）被挂到耳机 DAC **0x10**，扬声器 DAC 0x11 无流（codec 实时转储确认）
2. SN6140 硬件怪癖：扬声器引脚 0x17 的实际信号源**跟随耳机引脚 0x16 的连接选择**
   （即 0x16 指向哪个 DAC，0x17 就用哪个）
3. 未插耳机时 0x16 → 0x10 且 DAC 0x10 被静音（`Amp-Out vals: [0x80 0x80]`）→ 扬声器无声；
   插耳机时 0x10 解除静音 → 耳机正常
4. 修复验证（hda-verb）：两引脚都改接 0x10 + 解除 0x10 静音后，扬声器与模拟耳机均正常发声
5. EAPD 由驱动 `cx_init` → `cx_auto_turn_eapd` 已在开机时使能，无需处理
6. 上游驱动对 SSID `0x19e5:0x329e` 无任何 quirk 覆盖（现有 0x3289 条目是另一机型、仅 pin 配置）

## 3. 现状：用户态临时修复（已安装，2026-08-30）

- `/usr/local/sbin/sn6140-watchdog`：每 2 秒检查 codec，驱动/用户态重新静音 DAC 0x10 时重新注入 verb
- systemd 服务 `sn6140-watchdog.service` + system-sleep 钩子
- 局限：用户态轮询方案；模拟耳机插入时扬声器同时响（硬件共享 DAC 的固有限制）
- 测试内核 patch 期间会 `systemctl stop sn6140-watchdog`，验证通过后可卸载

## 4. Patch 设计（方案 A：机型专属 quirk）

文件：`sound/hda/codecs/conexant.c`（上游 master）

### 4.1 枚举新增

```c
enum {
    ...
    CXT_FIXUP_MATEBOOK14_SN6140,
};
```

### 4.2 fixup 函数

```c
/* Huawei MateBook 14 (SN6140): the speaker output follows the headphone
 * pin's connection select in hardware.  Both pins must be routed to the
 * shared DAC 0x10, which carries the playback stream; the generic
 * parser mutes that DAC when no headphone is plugged, silencing the
 * speaker.  Suppress the auto-mute and keep the shared DAC unmuted.
 */
static void cxt_fixup_matebook14_sn6140(struct hda_codec *codec,
					const struct hda_fixup *fix, int action)
{
	struct conexant_spec *spec = codec->spec;

	if (action == HDA_FIXUP_ACT_PRE_PROBE) {
		spec->gen.suppress_auto_mute = 1;
		return;
	}
	if (action != HDA_FIXUP_ACT_INIT)
		return;
	/* route both pins to the shared DAC 0x10 and unmute it */
	snd_hda_codec_write(codec, 0x16, 0, AC_VERB_SET_CONNECT_SEL, 0);
	snd_hda_codec_write(codec, 0x17, 0, AC_VERB_SET_CONNECT_SEL, 0);
	snd_hda_codec_amp_stereo(codec, 0x10, HDA_OUTPUT, 0,
				 HDA_AMP_MUTE, 0);
}
```

### 4.3 fixup 表注册与 quirk 条目

```c
[CXT_FIXUP_MATEBOOK14_SN6140] = {
    .type = HDA_FIXUP_FUNC,
    .v.func = cxt_fixup_matebook14_sn6140,
},
...
SND_PCI_QUIRK(0x19e5, 0x329e, "Huawei MateBook 14", CXT_FIXUP_MATEBOOK14_SN6140),
```

### 4.4 待确认项（实现阶段实测判定）

- 拔耳机后的重新静音来源：
  - 若为驱动 automute → fixup 中加 `automute_hook` 覆盖（每次 update_outputs 后重新 unmute）
  - 若为 WirePlumber 写 kctl → 换策略（备选：不创建独立 Headphone switch kctl；设计文档更新后再定）

## 5. 测试方案

准备：Ubuntu 7.0.0-30 内核源码获取 `conexant.c`（`apt source` 或 Ubuntu kernel git），
比对上游后打 patch；DKMS 仅编译 `snd-hda-codec-conexant.ko`。

| 编号 | 场景 | 通过标准 |
|------|------|----------|
| T0 | 停 watchdog、原生模块 | 扬声器无声（基线确认） |
| T1 | 安装 patch 模块、重启 | 开机即有声，无用户态脚本依赖 |
| T2 | 插拔 3.5mm 耳机 | 拔掉后扬声器持续有声 |
| T3 | 休眠→恢复 | 扬声器有声 |
| T4 | 回归：USB 耳机/麦克风/音量键/无爆音 | 全部正常 |
| T5 | 卸载 DKMS 模块 | 干净回滚 |

## 6. 提交流程

1. 基于 upstream master `git format-patch`
2. 标题：`ALSA: hda/conexant: Fix silent speaker on Huawei MateBook 14 (SN6140)`
3. 正文含硬件怪癖、根因、fixup 行为、T0-T5 测试记录；`Signed-off-by` 用用户真名与邮箱
4. 发送 alsa-devel（linux-sound@vger.kernel.org），CC Takashi Iwai、Jaroslav Kysela（`get_maintainer.pl`）
5. 备好答复：为何仅 quirk 单 SSID（只实测一台机器）；suppress_auto_mute 副作用（插耳机时扬声器同响，硬件共享 DAC 固有限制）；附 codec 转储

## 7. 风险与回滚

- 编译/安装内核模块有系统级影响：通过 DKMS 单模块构建 + T5 卸载验证控制
- quirk 仅匹配 SSID 0x19e5:0x329e，不影响其它机型
- 用户态 watchdog 随时可重新启用兜底
