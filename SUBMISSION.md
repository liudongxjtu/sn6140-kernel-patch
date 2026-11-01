# 上游提交材料

## 主线合入状态（2026-11-01 确认）✅

- **已进入主线**：commit `b57f5571a3e8`（`ALSA: hda/conexant: Fix silent
  speaker on Huawei MateBook 14 (SN6140)`），作者 Liu Eason，Takashi Iwai
  于 2026-09-28 提交进 for-next；内核 v7.3（2026-10-18 发布）之后随 7.4
  合并窗口进入 torvalds/linux master（2026-11-01 经 GitHub compare API 核实）。
- **首个包含它的正式内核**：v7.4（按 7.2→7.3 两个月节奏，预计 2026-12
  中下旬发布）。v7.0/v7.1/v7.2/v7.3 均不含；提交未标 Cc: stable，
  不会自动回移植到 7.x.y 稳定版。
- **stable 分支现状**（2026-11-01，kernel.org）：7.3.y 仍在维护，
  7.0/7.2 已 EOL。
- **主线链接**：
  - commit 页：https://github.com/torvalds/linux/commit/b57f5571a3e8
  - 文件历史：https://github.com/torvalds/linux/commits/master/sound/hda/codecs/conexant.c
  - git.kernel.org：https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=b57f5571a3e88febd38d60f9a9cefd8937a383ba
  - 邮件线程（含 "Applied to for-next" 回复）：https://lore.kernel.org/linux-sound/87a4pjom3r.wl-tiwai@suse.de/

## 发行版获取时间与本地处置

- Ubuntu 26.04（内核 7.0 系列）预计经 **26.04.2 的 HWE 内核**（约
  2027-02）自动获得（本机已装 `linux-generic-hwe-26.04`）；Ubuntu 27.04
  （约 2027-04）原生自带。
- 提前拿到的唯一官方途径：向 Canonical 提 SRU 请求——Launchpad 给 linux
  包报 bug，附本 commit，请求 backport 到 resolute（26.04）。
- 升级到含 quirk 的内核后：自编译模块不再需要（新内核目录不会自动携带）；
  清理 `/etc/modprobe.d/sn6140-conexant-first.conf`；看护进程按测试协议
  （开机/休眠/插拔/一周）实测通过后再退役。

## v2 提交记录（2026-09-19）

v1 曾被 Takashi Iwai 回复（邮件空格被破坏 + Sir/Madam 问候 + 名字拼写）：
- v2 使用 git send-email 保证空白完整
- 名字改为西式拼写 Liu Dong（若姓氏拆分不对请告知修改）
- 无问候语；changelog 放在 `---` 之后（不进 commit log）

## 发送方式

方法一（推荐，git send-email）：

```bash
cd /home/eason/0.code/0.my.sn6140-kernel-patch/upstream
git send-email --to linux-sound@vger.kernel.org \
  --cc "Takashi Iwai <tiwai@suse.de>" \
  --cc "Jaroslav Kysela <perex@perex.cz>" \
  /home/eason/0.code/0.my.sn6140-kernel-patch/0001-*.patch
```

方法二（普通邮件客户端）：新建邮件，把 patch 文件内容全文粘贴为正文
（纯文本模式），主题与 patch 的 Subject 一致：

    [PATCH] ALSA: hda/conexant: Fix silent speaker on Huawei MateBook 14 (SN6140)

收件人：linux-sound@vger.kernel.org
抄送：Takashi Iwai <tiwai@suse.de>、Jaroslav Kysela <perex@perex.cz>

## 审查预案

1. **为何只 quirk 单一 SSID**
   只实测了 19e5:329e（MateBook 14）；其它 SN6140 机型（14s/16s/X Pro 等）
   的引脚拓扑与静音行为可能不同。上游已有同类先例：SSID 19e5:3289 的华为
   quirk（commit d152afd1cd7a，Zhang Heng，2026-08-07）修的是耳机孔识别，
   与本 patch 的扬声器无声问题不同——按 SSID 逐个 quirk 是既有模式。

2. **suppress_auto_mute 的副作用**
   插入 3.5mm 耳机时扬声器会同时响——这是硬件共享 DAC 0x10 的固有限制
   （扬声器引脚跟随耳机引脚的连接选择），与修复前耳机路径的行为一致；
   USB 耳机完全不受影响。

3. **移除 mute switch（snd_hda_override_amp_caps）的理由与时机**
   共享 DAC 的静音开关会被路径停用逻辑（未插耳机时停用 HP 路径）以及
   用户态路由切换写静音，导致扬声器无声。注意必须在 ACT_PROBE 执行：
   PRE_PROBE 时 codec regmap 尚未初始化，snd_hdac_override_parm 会
   返回 -EINVAL 静默失败。移除后音量仍由现有 kctl 控制。

4. **测试记录**（测试环境：Ubuntu 26.04，内核 7.0.0-30 与 7.0.0-31，
   PipeWire 1.6.2）
   - T1 开机即有声，无任何用户态辅助脚本：通过（两个内核均验证）
   - T3 休眠→唤醒后持续有声：通过（2026-09-12 实测，恢复后 codec 状态
     验证 DAC 0x10 未静音、引脚路由保持 0x10）
   - 实际使用 6+ 天、多次重启、codec 绑定与 fixup 每次生效：通过
   - 内核由 30 升级到 31 后按同样方法重建模块、再次验证开机：通过
   - T2 耳机插拔 / T4 回归（USB 耳机、麦克风、音量键）：
     【待补充测试结果后更新 commit message 的 Tested 段】

5. **固定增益 -30dB（0x40）的理由**
   共享 DAC 的音量 kctl 归属耳机路径（用户态音量不驱动它）。0dB 满增益时
   软件音量一格即过响；固定 -30dB 让 PipeWire 数字音量获得可用调节范围
   （本机实测合适）。若维护者要求增益跟随音量 kctl，需进一步改路径模型。

6. **如需 codec 级方案**
   将 quirk 条件从 SSID 改为 vendor_id 0x14f11f87 判定，另行迭代 v2。

## 附件

- patch: `0001-ALSA-hda-conexant-Fix-silent-speaker-on-Huawei-MateB.patch`
- 设计文档: `docs/2026-08-30-sn6140-matebook14-audio-fix-design.md`
- 实现计划: `docs/2026-08-30-sn6140-kernel-patch.md`
- 内核源码改动（Ubuntu 树）: 本地留存 `linux-source-7.0.0/`（已 gitignore，不入库）
