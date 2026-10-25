# SN6140 MateBook 14 内核 Patch 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 Huawei MateBook 14（SSID 0x19e5:0x329e，SN6140 codec）编写并实测一个 conexant 驱动 quirk patch，修复内置扬声器无声，并产出可提交 alsa-devel 的补丁。

**Architecture:** 在 Ubuntu 内核源码（linux-source-7.0.0）的 conexant.c 上实现 `CXT_FIXUP_MATEBOOK14_SN6140`（PRE_PROBE 设 suppress_auto_mute，INIT 路由两引脚至共享 DAC 0x10 并解除静音），本地编译单模块实测 T0-T5，最后基于 upstream master 重新生成 format-patch 与提交邮件。

**Tech Stack:** Linux 内核 7.0.0-30（Ubuntu 26.04）、C（HDA codec 驱动）、make、DKMS 替代方案为 in-tree 单模块构建、systemd（测试期间管理 watchdog 服务）、git format-patch。

## Global Constraints

- 设计文档：`/home/eason/0.code/docs/superpowers/specs/2026-08-30-sn6140-matebook14-audio-fix-design.md`（所有改动以其为准）
- 与设计文档的一处偏差：本地构建用 **in-tree 单模块构建 + .ko 备份回滚** 替代 DKMS（相同目标：只编译一个模块、可干净卸载；in-tree 构建失败模式更少），已在任务 3 实现
- 所有 sudo 命令必须由用户在会话中执行（`! sudo ...` 前缀）；计划中标注 **[USER]**
- 测试期间 watchdog 必须停止（T0 前 `disable --now`），否则它会掩盖 patch 行为
- quirk 只允许匹配 SSID `0x19e5:0x329e`，不得影响其它机型
- 上游 patch 必须基于 upstream master 的 `sound/hda/codecs/conexant.c`（已下载到 `/tmp/conexant-master.c`）
- 工作目录：`/home/eason/0.code/sn6140-kernel-patch/`（本计划内 git init 跟踪）
- 内核配置来源：`/boot/config-7.0.0-30-generic`

---

### Task 1: 环境准备（内核源码 + 构建工具）

**Files:**
- Create: `/home/eason/0.code/sn6140-kernel-patch/`（git 仓库）
- Extract: `linux-source-7.0.0/`（内核源码树，位于工作目录内）

**Interfaces:**
- Consumes: 无
- Produces: `/home/eason/0.code/sn6140-kernel-patch/linux-source-7.0.0/sound/hda/codecs/conexant.c`（可编译的源码树）、`.config` 就绪

- [ ] **Step 1: 创建工作目录并初始化 git**

```bash
mkdir -p /home/eason/0.code/sn6140-kernel-patch && cd /home/eason/0.code/sn6140-kernel-patch && git init
```

- [ ] **Step 2: [USER] 安装构建工具与内核源码包**

```bash
! sudo apt install -y build-essential libelf-dev flex bison linux-source-7.0.0
```

若 `linux-source-7.0.0` 不存在，改用：`! sudo apt install -y linux-source`

- [ ] **Step 3: 解压内核源码**

```bash
cd /home/eason/0.code/sn6140-kernel-patch
tar -xjf /usr/src/linux-source-7.0.0.tar.bz2
ls linux-source-7.0.0/sound/hda/codecs/conexant.c
```

预期：输出 `linux-source-7.0.0/sound/hda/codecs/conexant.c`

- [ ] **Step 4: 准备内核配置并 modules_prepare**

```bash
cd /home/eason/0.code/sn6140-kernel-patch/linux-source-7.0.0
cp /boot/config-7.0.0-30-generic .config
make olddefconfig
make modules_prepare -j$(nproc)
```

预期：`make modules_prepare` 退出码 0，无 fatal error（约 2-5 分钟）

- [ ] **Step 5: 确认目标模块可构建（打 patch 前的冒烟测试）**

```bash
make sound/hda/codecs/snd-hda-codec-conexant.ko -j$(nproc)
ls -la sound/hda/codecs/snd-hda-codec-conexant.ko
```

预期：生成 `snd-hda-codec-conexant.ko`。若单目标构建失败，改用 `make M=sound/hda/codecs modules`（构建该目录全部 codec 模块，取其中 conexant.ko）。

- [ ] **Step 6: Commit**

```bash
cd /home/eason/0.code/sn6140-kernel-patch
echo "linux-source-7.0.0/" > .gitignore
git add .gitignore linux-source-7.0.0/sound/hda/codecs/conexant.c
git commit -m "chore: import ubuntu 7.0.0-30 conexant.c for patching"
```

（`.gitignore` 忽略整个源码树，conexant.c 单独 add 以便跟踪 patch 前后差异）

---

### Task 2: 在 Ubuntu 源码上实现 quirk patch

**Files:**
- Modify: `linux-source-7.0.0/sound/hda/codecs/conexant.c`

**Interfaces:**
- Consumes: Task 1 的源码树
- Produces: 打上 `CXT_FIXUP_MATEBOOK14_SN6140` 的 conexant.c；后续任务的 diff 基准

- [ ] **Step 1: 比对 Ubuntu 源码与 upstream master，确认插入锚点**

```bash
diff /tmp/conexant-master.c /home/eason/0.code/sn6140-kernel-patch/linux-source-7.0.0/sound/hda/codecs/conexant.c | head -40
```

若 diff 为空或极小 → 插入锚点与 master 一致；若 Ubuntu 版本差异大，则按下列锚点内容在 Ubuntu 文件中定位：
- 枚举区：`CXT_FIXUP_...` 定义块（grep `enum {` 与 `CXT_FIXUP` 首个定义）
- fixup 表：`cxt_fixups[]` 结构体结尾（`};` 前最后一个 fixup 条目）
- quirk 表：含 `SND_PCI_QUIRK(0x19e5, 0x3289` 的表

- [ ] **Step 2: 在枚举末尾新增 fixup ID**

在枚举块（`CXT_FIXUP_...` 系列）的最后一个条目之后、`};` 之前插入：

```c
	CXT_FIXUP_MATEBOOK14_SN6140,
```

- [ ] **Step 3: 新增 fixup 函数**（放在 `cx_init` 之前或其它 fixup 函数旁，如 `cxt_fixup_hp_a_u` 附近）

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

- [ ] **Step 4: 在 fixup 表注册**

在 `cxt_fixups[]`（或对应表）内、结尾 `};` 前插入：

```c
	[CXT_FIXUP_MATEBOOK14_SN6140] = {
		.type = HDA_FIXUP_FUNC,
		.v.func = cxt_fixup_matebook14_sn6140,
	},
```

- [ ] **Step 5: 在 quirk 表新增条目**（在 `SND_PCI_QUIRK(0x19e5, 0x3289, ...)` 行之后）

```c
	SND_PCI_QUIRK(0x19e5, 0x329e, "Huawei MateBook 14", CXT_FIXUP_MATEBOOK14_SN6140),
```

- [ ] **Step 6: 编译验证（仅编译，不安装）**

```bash
cd /home/eason/0.code/sn6140-kernel-patch/linux-source-7.0.0
make sound/hda/codecs/snd-hda-codec-conexant.ko -j$(nproc)
```

预期：退出码 0，无 warning 指向新函数（对照 Step 5 冒烟结果）

- [ ] **Step 7: 检查改动并 commit**

```bash
git diff --stat linux-source-7.0.0/sound/hda/codecs/conexant.c
git add linux-source-7.0.0/sound/hda/codecs/conexant.c
git commit -m "wip: add CXT_FIXUP_MATEBOOK14_SN6140 to ubuntu conexant.c"
```

预期 diff 统计：1 文件，约 +30 行。

---

### Task 3: 备份并安装 patched 模块

**Files:**
- Modify: `/lib/modules/7.0.0-30-generic/kernel/sound/hda/codecs/snd-hda-codec-conexant.ko.zst`（先备份）
- Create: `/lib/modules/7.0.0-30-generic/kernel/sound/hda/codecs/snd-hda-codec-conexant.ko`（新模块）

**Interfaces:**
- Consumes: Task 2 编译产物 `snd-hda-codec-conexant.ko`
- Produces: 系统加载 patched 模块；备份文件 `*.ko.zst.orig` 供 T5 回滚

- [ ] **Step 1: [USER] 备份原生模块**

```bash
! sudo cp /lib/modules/7.0.0-30-generic/kernel/sound/hda/codecs/snd-hda-codec-conexant.ko.zst \
     /lib/modules/7.0.0-30-generic/kernel/sound/hda/codecs/snd-hda-codec-conexant.ko.zst.orig
! sudo ls -la /lib/modules/7.0.0-30-generic/kernel/sound/hda/codecs/
```

预期：目录中同时存在 `.ko.zst` 与 `.ko.zst.orig`

- [ ] **Step 2: [USER] 安装新模块并重建模块索引**

```bash
! sudo cp /home/eason/0.code/sn6140-kernel-patch/linux-source-7.0.0/sound/hda/codecs/snd-hda-codec-conexant.ko \
     /lib/modules/7.0.0-30-generic/kernel/sound/hda/codecs/
! sudo rm /lib/modules/7.0.0-30-generic/kernel/sound/hda/codecs/snd-hda-codec-conexant.ko.zst
! sudo depmod -a
```

（移除原 `.ko.zst` 避免 modprobe 二义性；备份 `.orig` 留在原目录）

- [ ] **Step 3: [USER] 重载声卡驱动栈**

```bash
! sudo systemctl disable --now sn6140-watchdog.service
! sudo modprobe -r snd_hda_codec_conexant snd_hda_intel && sudo modprobe snd_hda_intel
```

预期：`modprobe` 退出码 0。若 `-r` 报 busy（有进程占用），重启一次代替。

- [ ] **Step 4: 确认新模块已加载且 fixup 生效**

```bash
dmesg | grep -iE "conexant|SN6140" | tail -5
```

预期：`SN6140: BIOS auto-probing` 行存在（fixup 为静默生效，无独立日志）

---

### Task 4: 执行 T0-T5 测试协议（含静音来源判定与 fallback 迭代）

**Files:**
- Modify（条件性，仅 T2 判定为 WirePlumber 时）: `linux-source-7.0.0/sound/hda/codecs/conexant.c`

**Interfaces:**
- Consumes: Task 3 的已安装模块
- Produces: 测试记录（写入 `docs/superpowers/plans/` 同目录 `sn6140-test-log.md`）、必要时含 fallback 修改的第二版模块

- [ ] **Step 1: T0 基线确认**——watchdog 已停（Task 3 Step 3），播放测试音并确认扬声器无声

```bash
speaker-test -D pipewire -c 2 -t sine -f 440 -l 4
grep -A9 "Node 0x10 " /proc/asound/card0/codec#0 | grep "Amp-Out"
```

预期：**无声**（原生行为：DAC 0x10 被静音或路由错配）。注意：此时加载的是 patched 模块——若此步就有声，说明 fixup 已生效，直接跳到 Step 3。

- [ ] **Step 2: T1 开机自验证**——[USER] 重启，开机后不运行任何脚本直接播放

```bash
# 重启后：
! systemctl is-active sn6140-watchdog   # 预期 inactive
speaker-test -D pipewire -c 2 -t sine -f 440 -l 4
```

预期：**有声**（fixup 在 probe 时生效）

- [ ] **Step 3: T2 插拔判定**——播放中插拔 3.5mm 耳机，检查 DAC 0x10 状态

```bash
speaker-test -D pipewire -c 2 -t sine -f 440 -l 30 &   # 长音
# [USER] 插入耳机 2 秒 → 拔出
grep -A9 "Node 0x10 " /proc/asound/card0/codec#0 | grep "Amp-Out"
grep -A13 "Node 0x1[67] " /proc/asound/card0/codec#0 | grep -E "Connection:|0x1[01]"
kill %1
```

判定：
- **拔后 `Amp-Out vals` 无 `0x80` 且扬声器持续有声** → 静音来源是驱动 automute，已由 `suppress_auto_mute` 消除 → 跳到 Step 5
- **拔后重新 `[0x80 0x80]`** → 静音来源是 WirePlumber 写 kctl → 执行 Step 4

- [ ] **Step 4: （仅 T2 失败时）fallback 修改：移除共享 DAC 的静音能力**

修改 `cxt_fixup_matebook14_sn6140` 的 PRE_PROBE 分支为：

```c
	if (action == HDA_FIXUP_ACT_PRE_PROBE) {
		unsigned int caps;

		spec->gen.suppress_auto_mute = 1;
		/* Remove the mute switch on the shared DAC so that
		 * userspace (WirePlumber) can't mute it when the
		 * headphone port becomes unavailable.
		 */
		caps = query_amp_caps(codec, 0x10, HDA_OUTPUT);
		snd_hda_override_amp_caps(codec, 0x10, HDA_OUTPUT,
					  caps & ~AC_AMPCAP_MUTE);
		return;
	}
```

然后重编译、重装（重复 Task 3 Step 2-3 的 cp/rm/depmod/modprobe）、重跑 Step 3 判定。
预期：拔耳机后 DAC 0x10 不再出现 `0x80`，扬声器持续有声。

- [ ] **Step 5: T3 休眠恢复**——[USER] `systemctl suspend`，手动唤醒后播放测试音

预期：恢复后扬声器有声（EAPD 由 `cx_init` 在恢复路径重新使能，路由 fixup 亦然）

- [ ] **Step 6: T4 回归**——依次验证并记录：

```bash
# USB 耳机：插入后 wpctl status 出现新 sink 且正常出声
# 内置麦克风：arecord -D pipewire -d 3 /tmp/mic.wav 后播放该文件确认录音正常
# 音量键：Fn 音量键调节时音量变化（PipeWire 数字音量，不受影响）
# 爆音：开机、插拔、休眠恢复时听是否有异常爆音
```

预期：全部正常；任何异常记入测试日志并停止提交流程。

- [ ] **Step 7: T5 回滚验证**——[USER]

```bash
! sudo rm /lib/modules/7.0.0-30-generic/kernel/sound/hda/codecs/snd-hda-codec-conexant.ko
! sudo mv /lib/modules/7.0.0-30-generic/kernel/sound/hda/codecs/snd-hda-codec-conexant.ko.zst.orig \
     /lib/modules/7.0.0-30-generic/kernel/sound/hda/codecs/snd-hda-codec-conexant.ko.zst
! sudo depmod -a
! sudo modprobe -r snd_hda_codec_conexant snd_hda_intel && sudo modprobe snd_hda_intel
```

预期：扬声器回到无声（原生行为）——确认回滚干净；随后按 Task 3 重新装回 patched 模块继续日常使用（watchdog 保持 disabled）。

- [ ] **Step 8: 记录测试结果并 commit**

将 T0-T5 结果写入 `docs/superpowers/plans/sn6140-test-log.md`，并在工作仓库 commit。

---

### Task 5: 基于 upstream master 生成提交用 patch

**Files:**
- Create: `/home/eason/0.code/sn6140-kernel-patch/upstream/`（合成 git 仓库，仅含 conexant.c）
- Create: `/home/eason/0.code/sn6140-kernel-patch/0001-ALSA-hda-conexant-Fix-silent-speaker-on-Huawei-MateB.patch`

**Interfaces:**
- Consumes: `/tmp/conexant-master.c`（upstream master 版）、Task 2/4 的最终 fixup 代码
- Produces: `*.patch` 文件 + commit message（Signed-off-by 待用户署名后补）

- [ ] **Step 1: 建立合成仓库并导入 master 版 conexant.c**

```bash
cd /home/eason/0.code/sn6140-kernel-patch
mkdir -p upstream/sound/hda/codecs && cd upstream && git init
cp /tmp/conexant-master.c sound/hda/codecs/conexant.c
git add . && git commit -m "import sound/hda/codecs/conexant.c from upstream master"
```

- [ ] **Step 2: 应用与 Task 2/4 相同的最终修改**（枚举、fixup 函数、fixup 表、quirk 条目；若执行了 Task 4 Step 4 的 fallback，用其最终版）

- [ ] **Step 3: 向用户索取署名信息并 commit**

```bash
git add sound/hda/codecs/conexant.c
git commit -m "ALSA: hda/conexant: Fix silent speaker on Huawei MateBook 14 (SN6140)

On the Huawei MateBook 14 (PCI SSID 19e5:329e), the SN6140 codec
silently routes the speaker output through the headphone pin's
connection select: whatever DAC the headphone pin 0x16 is connected to,
the speaker pin 0x17 follows.  The generic parser attaches the playback
stream to DAC 0x10 (shared by the headphone path) and mutes that DAC
when no headphone is plugged, which silences the internal speaker while
the headphone jack keeps working.

Add a quirk for this machine that suppresses the auto-mute and, at
init, routes both pins to the shared DAC 0x10 and unmutes it.  EAPD
needs no special handling as the driver already enables it for all
EAPD pins at init.

Tested on Ubuntu 26.04 (kernel 7.0.0-30): speaker plays at boot, after
headphone plug/unplug cycles and after suspend/resume; USB headset,
internal mic and volume keys unaffected.

Signed-off-by: <用户真名> <用户邮箱>"
```

（`git commit` 会打开编辑器：用上面的 message 完整替换；`Signed-off-by` 两处占位符先向用户索取真名与邮箱后填入，不得虚构）

- [ ] **Step 4: 生成 patch 文件**

```bash
git format-patch -1 -o /home/eason/0.code/sn6140-kernel-patch/
ls /home/eason/0.code/sn6140-kernel-patch/0001-*.patch
```

预期：生成 `0001-ALSA-hda-conexant-Fix-silent-speaker-on-Huawei-MateB.patch`

- [ ] **Step 5: 用 `git apply --check` 自检 patch**

```bash
cd /home/eason/0.code/sn6140-kernel-patch/upstream
git stash 2>/dev/null; git checkout HEAD~1 -- sound/hda/codecs/conexant.c
git apply --check /home/eason/0.code/sn6140-kernel-patch/0001-*.patch && echo "apply OK"
```

预期：`apply OK`

---

### Task 6: 提交材料与本地收尾

**Files:**
- Create: `/home/eason/0.code/sn6140-kernel-patch/SUBMISSION.md`（邮件正文草稿）
- Delete: watchdog 的 systemd 单元与脚本（仅当 T1-T5 全通过后）

**Interfaces:**
- Consumes: Task 5 的 patch 文件与测试日志
- Produces: 可发送的邮件草稿；系统恢复无 watchdog 的干净状态

- [ ] **Step 1: 获取维护者邮件列表**

无需脚本：HDA 补丁标准收件人（`scripts/get_maintainer.pl` 在无完整内核树时无法运行，使用固定列表）：
- `linux-sound@vger.kernel.org`（主列表，原 alsa-devel）
- `tiwai@suse.de`（Takashi Iwai，sound 子系统维护者）
- `perex@perex.cz`（Jaroslav Kysela）

- [ ] **Step 2: 写 SUBMISSION.md 邮件草稿**

```markdown
To: linux-sound@vger.kernel.org
Cc: Takashi Iwai <tiwai@suse.de>, Jaroslav Kysela <perex@perex.cz>
Subject: [PATCH] ALSA: hda/conexant: Fix silent speaker on Huawei MateBook 14 (SN6140)

（正文：patch 文件内容直接作为正文；开头加一段说明——硬件怪癖、测试环境
Ubuntu 26.04 / 7.0.0-30、T0-T5 测试结果摘要、codec 转储可应要求提供。

附注审查预案：
1. "为何只 quirk 单一 SSID" → 只实测了这台机器；其它 SN6140 机型
   （14s/16s/X Pro 等）拓扑可能不同，欢迎后续贡献者扩展
2. suppress_auto_mute 副作用 → 插 3.5mm 耳机时扬声器同时响，是硬件
   共享 DAC 的固有限制，与现有行为一致（USB 耳机不受影响）
3. 若维护者要求 codec 级方案 → 将 quirk 条件从 SSID 改为 vendor_id
   0x14f11f87 判断，另行迭代 v2
）
```

- [ ] **Step 3: [USER] 本地收尾——卸载 watchdog（T1-T5 全通过后）**

```bash
! sudo systemctl disable --now sn6140-watchdog.service
! sudo rm /etc/systemd/system/sn6140-watchdog.service /usr/local/sbin/sn6140-watchdog /usr/lib/systemd/system-sleep/sn6140-watchdog
! sudo systemctl daemon-reload
```

预期：`systemctl is-active sn6140-watchdog` 报 inactive，系统由 patched 内核模块独立工作。

- [ ] **Step 4: 更新记忆文件**

更新 `/home/eason/.claude/projects/-home-eason-0-code/memory/matebook-sn6140-audio-fix.md`：追加「内核 patch 已本地化（conexant.c quirk），watchdog 已移除；上游提交状态：<pending/已发送/已合并>」及关键路径。

- [ ] **Step 5: 最终 commit 与汇总**

```bash
cd /home/eason/0.code/sn6140-kernel-patch && git add -A && git commit -m "docs: add submission draft and finalize patch"
```

向用户汇报：patch 路径、测试记录路径、发送命令参考：

```bash
git send-email --to linux-sound@vger.kernel.org \
  --cc "Takashi Iwai <tiwai@suse.de>" --cc "Jaroslav Kysela <perex@perex.cz>" \
  /home/eason/0.code/sn6140-kernel-patch/0001-*.patch
```

（用户按其邮箱配置自行执行发送）
