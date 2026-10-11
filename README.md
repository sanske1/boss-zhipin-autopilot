# boss-zhipin-autopilot

用 **adb 驱动真机上的 BOSS直聘 App** 做半自动求职投递的 Claude Code Skill。

把机械劳动交给脚本——开 App、切页、排序、点卡片、读 JD 全文、返回、滚动、推进游标、去重；
把判断留给人——这条到底投不投，必须读完了 JD 再说。

> **一句话原则：循环可以有，判定不能省。**

---

## 它解决什么问题

在 BOSS直聘 上认真找工作，人工的瓶颈不是「点按钮」，而是「一条条读 JD 再判断」。
但大多数自动投递脚本恰恰把这两件事搞反了：它们替你点，却不替你读。

这个项目把两者切开：

| 环节 | 谁做 |
|---|---|
| 打开 App / 切页 / 排序 / 点卡片 / 读 JD / 返回 / 滚动 / 推进游标 / 去重 | **脚本** |
| 读 JD 正文 → 对照简历打分 → 决定投不投（4-C） | **人 / Agent** |

**4-C 是整个流程里唯一的介入点**，其余步骤全自动。脚本不提供任何「批量投递」入口 ——
所以它结构上就没给盲投留位置。

## 为什么用真机而不是网页

- 手机端推荐流的质量通常更高，网页版容易漏；
- 真实用户操作，比模拟接口的风控风险低；
- 登录态用你自己的，脚本不碰账号密码。

## 环境要求

| 项 | 要求 |
|---|---|
| 手机 | Android，开启「开发者选项 → USB 调试」，USB 直连并授权 |
| App | 手机装好 BOSS直聘 并**已登录**（登录要人工做） |
| 电脑 | **Windows + Git Bash**（解析 UI dump 的两个脚本是 PowerShell） |
| adb | 在 PATH 里，或设环境变量 `ADB` 指向可执行文件 |

```bash
export ADB="<你的 adb 路径>"     # 已在 PATH 里可省略
export MSYS_NO_PATHCONV=1        # Git Bash 下必须，否则 /sdcard/... 会被转义
```

> 想让它跨平台？把 `tools/cards.ps1`、`tools/extract_jd.ps1` 换成 Python（标准库 `xml.etree` 就够，
> 逻辑很短）即可 —— 这是最值得提的第一个 PR。

## 快速开始

```bash
git clone <this-repo> && cd boss-zhipin-autopilot
export MSYS_NO_PATHCONV=1

adb devices                                  # ① 确认手机连上
adb shell am start -n com.hpbr.bosszhipin/.module.launcher.WelcomeActivity   # ② 开 App

cp templates/投递标准.md ./投递标准.md        # ③ 写清你不投什么、什么算对口
cp templates/简历.md     ./简历.md            #    写清你会什么、不会什么
cp templates/投递记录.md ./投递记录.md

adb shell input tap 135 2287                 # ④ 切到「职位」
adb shell input tap 387 422                  #    按「最新」排序

OUT=$(bash tools/next_card.sh)               # ⑤ 下一张该点哪 → "540 786 某某公司"
set -- $OUT; adb shell input tap "$1" "$2"   #    点开
bash tools/read_jd.sh                        # ⑥ 读完整 JD（自动展开「查看更多」）
# —— ⑦ 这里由你/Agent 按投递标准判定 ——
bash tools/read_jd.sh -v 投 -r "理由"        # ⑧ 落盘
adb shell input tap 540 2255                 #    投：立即沟通
adb shell input tap 82 163; adb shell input tap 99 152   #    返回两次回到列表
```

完整的循环、判定规则、踩过的坑，见 **[SKILL.md](SKILL.md)**。

## 设计要点

**唯一入口，且不可逆的动作只有一个。** `tools/read_jd.sh` 只读；真正发消息的只有
4-D 那一次 `input tap 540 2255`（点「立即沟通」）。流程里没有任何批量投递路径。

**去重靠记录文件。** 已沟通过的职位不会从列表消失，所以每轮都拿列表页的公司名去
`投递记录.md` 里比对，跳过处理过的。

**公司名来自列表页，不是详情页。** 部分职位详情页没有招聘者行，从详情页取不到公司名；
`next_card.sh` 会把选中卡的名字写进 `tools/.last_company`，`read_jd.sh` 写记录时优先用它 ——
否则去重会失效、同一张卡反复出现。

**每条都留痕。** 判否也必须写理由，否则事后复盘时分不清「当时为什么没投」。

## 安全与边界

- **点「立即沟通」会立刻以你的名义发出一条招呼语，发出即达、不可撤回。**
  请先读完 JD 再决定，一次只点一条。
- 重复点已沟通过的职位不会重发招呼语，只会打开已有会话。
- 连续定位/读页失败 3 次，或遇到未知弹窗 → 停手交给人工，不要硬试。
- 出现静默触顶（按钮没变化但没发出去）→ 立刻停，不要重试。
- 平台规则会变。**慢一点、少一点、每条都真读**，是这套流程能长期跑下去的前提。
- 请自行确认你的使用方式符合 BOSS直聘 的用户协议与当地法律。作者不对账号风险负责。

## 装到 Claude Code

```bash
cp -r boss-zhipin-autopilot ~/.claude/skills/     # 个人级
# 或
cp -r boss-zhipin-autopilot .claude/skills/       # 项目级
```

之后对 Claude 说「用 BOSS 直聘投递流程接着跑」即可。

## 目录

```
SKILL.md                  # Skill 定义 + 完整工作流（本体）
tools/next_card.sh        # 找下一张未处理卡（去重 + 翻页）
tools/read_jd.sh          # 读 JD + 展开「查看更多」+ 写记录
tools/cards.ps1           # 解析列表页 UI dump
tools/extract_jd.ps1      # 解析详情页 UI dump
templates/                # 判定标准 / 简历 / 记录表 三份模板
```

## License

MIT
