---
name: boss-zhipin-autopilot
description: 用 adb 驱动真机上的 BOSS直聘 App 做半自动求职投递——脚本负责开 App、切页、排序、点卡片、读 JD、返回、滚动、推进游标、去重，人在唯一的介入点「4-C 判分」上读 JD 并对照简历打分，决定投不投。当用户想用手机端 BOSS直聘 批量筛选职位、读取岗位 JD 全文、按自己的简历标准决定要不要点「立即沟通」，或想在真机上自动化某个 App 的列表浏览 / 详情读取流程时使用。
---

# BOSS直聘 手机端 · 工作流

记录在真机上操作 BOSS直聘 的完整流程，每一步都含可直接复现的命令。

## 环境

| 项目 | 值 |
|---|---|
| 手机 | 任意 Android 手机，开启「开发者选项 → USB 调试」，USB 直连并授权 |
| 系统 | 实测 Android 14 |
| 连接方式 | USB 数据线直连 |
| 电脑 | **Windows + Git Bash**（脚本用 PowerShell 解析 UI dump，见下方说明） |
| adb | `tools/*.sh` 默认用 PATH 里的 `adb`；不在 PATH 就设环境变量 `ADB` 指向可执行文件 |

```bash
export ADB="<你的 adb 路径>"        # 已在 PATH 里就省略这行
export MSYS_NO_PATHCONV=1           # 见下方 Git Bash 注意
```

> ⚠️ **Git Bash 注意**：命令中出现 `/sdcard/...` 这类以 `/` 开头的路径时，MSYS 会错误转义成 `C:/Program Files/Git/sdcard/...`，需先 `export MSYS_NO_PATHCONV=1`。

> ⚠️ **平台说明**：`tools/cards.ps1` 和 `tools/extract_jd.ps1` 是 PowerShell 脚本，所以这套流程目前**只在 Windows + Git Bash 下能跑**。把这两个解析器换成 Python（标准库 `xml.etree` 即可，逻辑很短）是让它跨平台的第一步 PR。

---

## 执行模型

| 环节 | 执行者 |
|---|---|
| 打开 App / 切页 / 排序 / 点卡片 / 读 JD / 返回 / 滚动 / 推进游标 | **脚本自动执行** |
| **4-C 判分**（读 JD + 对照简历打 0–100 分 + 决定投否） | **人 / Agent 介入** |

- **4-C 是本流程中唯一的介入点**，其余步骤不介入。
- 推论：滚动/到底判定、游标持久化、已投去重、异常处理、节奏与日上限 —— 都属于**脚本职责**。
- 判定必须真实发生（见下方「循环的合法性边界」），不得由脚本伪造或跳过。

**4-C 执行方式**：读到 JD 后，按 [投递标准.md](templates/投递标准.md) **给出「判定 + 理由」并直接执行**（投 → 4-D；否 → 返回）。每张落盘到 [投递记录.md](templates/投递记录.md)。

**数据源**：先跑「职位页 → 最新排序」的推荐流；关键词搜索作为推荐流见底后的备选。若推荐流跑出问题，及时告知用户。

---

## 步骤 1：打开 BOSS直聘

**目标**：启动 BOSS直聘 App，并确认它已在前台运行。

**前置条件**：手机 USB 直连、已授权。

```bash
adb devices
# 期望输出包含(<serial>  device)
```

**操作**：

```bash
adb shell am start -n com.hpbr.bosszhipin/.module.launcher.WelcomeActivity
```

**验证**：

```bash
adb shell dumpsys window | grep mCurrentFocus
# 期望输出包含 com.hpbr.bosszhipin/...
```

**预期结果**（实测，已登录状态）：

- 前台窗口为 `com.hpbr.bosszhipin.module.main.activity.MainActivity`
- 界面停在**职位推荐页**：顶部「全职 / 实习 / 兼职」，下面是岗位卡片列表，底部导航「职位 / 发现 / 消息 / 我的」

> 若账号**未登录**，启动后会停在 `WelcomeActivity`「登录/注册」页，需先登录（登录必须人工做，脚本不碰账号密码）。

**关键信息**：

- 包名：`com.hpbr.bosszhipin`
- 入口 Activity：`.module.launcher.WelcomeActivity`（冷启动入口，会自动跳转）
- 主界面 Activity：`.module.main.activity.MainActivity`

---

## 步骤 2：点击底部「职位」按钮，确保停在求职页面

**目标**：无论 App 打开时停在哪个 tab，都切回「职位」（求职）页面。

**操作**：

```bash
adb shell input tap 135 2287
```

**元素定位**：

| 项 | 值 |
|---|---|
| 可点击容器 | `com.hpbr.bosszhipin:id/cl_tab_1` |
| 容器 bounds | `[0,2218][270,2356]` |
| 点击坐标（中心） | `135, 2287` |
| 文字节点 | `com.hpbr.bosszhipin:id/tv_tab_1`（text=`职位`） |

**验证**：重新 dump UI，确认「职位」节点 `selected="true"`：

```bash
adb shell uiautomator dump /sdcard/w2.xml
adb exec-out cat /sdcard/w2.xml | grep tv_tab_1
# 期望输出 selected="true"
```

**预期结果**：底部「职位」图标高亮，界面显示职位推荐列表。

**底部导航四个 tab 坐标**（备查）：

| tab | 可点击容器 id | 中心坐标 |
|---|---|---|
| 职位 | `cl_tab_1` | `135, 2287` |
| 发现 | `cl_tab_2` | `405, 2287` |
| 消息 | `cl_tab_3` | `675, 2287` |
| 我的 | `cl_tab_4` | `945, 2287` |

> 📐 下文所有坐标都是**实测机（1080×2400）**下的值。换分辨率要重新标：`adb shell uiautomator dump` 后从节点的 `bounds` 取中心，改的就是那几行 `input tap`。选卡片的坐标不用管 —— 那个由 `tools/next_card.sh` 每次现算。

---

## 步骤 3：点击顶部「最新」按钮（按最新排序）

**目标**：把岗位列表按「最新发布」排序。

**操作**：

```bash
adb shell input tap 387 422
```

**元素定位**：

| 项 | 值 |
|---|---|
| 可点击容器 | `FrameLayout`（无 resource-id） |
| 容器 bounds | `[321,363][454,481]` |
| 点击坐标（中心） | `387, 422` |
| 文字节点 | `com.hpbr.bosszhipin:id/tv_tab_label`（text=`最新`） |

**验证**：dump UI，确认「最新」文字节点 `selected="true"`（其余 `推荐`/`附近` 为 false）。

**预期结果**：顶部排序行「最新」高亮，列表刷新为最新发布岗位（卡片上出现「职位新发布」等标记）。

**顶部排序 tab 坐标**（备查）：

| tab | bounds | 中心坐标 |
|---|---|---|
| 推荐 | `[55,363][188,481]` | `121, 422` |
| 附近 | `[188,363][321,481]` | `254, 422` |
| 最新 | `[321,363][454,481]` | `387, 422` |

---

## 步骤 4：循环处理职位列表（循环判断）

> 本步骤为**循环**：对列表中的职位逐个处理。下列 **4-A / 4-B / 4-C / 4-D** 为循环体内的子步骤。

> ### ⚠️ 循环的合法性边界
>
> [投递标准.md](templates/投递标准.md) 里「**禁止脚本投递**」禁止的是 —— **不判、脚本盲投**（批量/循环自动投递）。**本流程允许循环**，前提是：
>
> - ✅ **每一张卡都必须真实读到 JD 正文，并打 0–100 适配度分**，据此决定是否投递；
> - ❌ **不允许跳过判定直接点「立即沟通」**；
> - ❌ **不允许凭标题 / 公司名 / 标签**下结论。
>
> 一句话：**循环可以有，判定不能省。** 每轮的 4-B（读 JD）→ 4-C（判分）是投递的**前置必要条件**，不是可选步骤。

### 4-A 点击第一个职位信息

**目标**：打开列表中「还没处理过」的职位详情页。

**前置**：当前在「职位」页（步骤 2），已按「最新」排序（步骤 3）。

**操作**：先用 `next_card.sh` 问「下一张该点哪」，再点。

```bash
OUT=NONE
for i in 1 2 3 4 5 6; do OUT=$(bash tools/next_card.sh); [ "$OUT" != "NONE" ] && break; \
  "$ADB" shell input swipe 540 1600 540 1000 900 >/dev/null 2>&1; sleep 2; done
set -- $OUT; "$ADB" shell input tap "$1" "$2"; sleep 3
```

`next_card.sh` 输出 `x y 公司`；同屏没有新卡就慢拖翻页，翻完 6 次输出 `NONE`。

**元素定位**：

| 项 | 值 |
|---|---|
| 卡片元素 | `LinearLayout`（clickable=true，无 resource-id） |
| 卡片内部公司名 | `com.hpbr.bosszhipin:id/tv_company_name` |

> ⚠️ **卡片阶段必须顺序点击，不得重复点击**
>
> - 循环维护一个**递增的卡片序号**：第 1 张 → 第 2 张 → 第 3 张 → …，每轮只前进一格；
> - **同一张卡片只点一次** —— 已处理过的卡片（无论 4-C 通过与否）**不再点第二次**；
> - 已沟通的职位**不会**从列表消失，所以「每次都点第 1 张」会永远卡在第一张；
> - `next_card.sh` 就是干这个的：拿列表页每张卡的公司名去 [投递记录.md](templates/投递记录.md) 里比对，跳过已处理的；
> - 列表滚动后坐标会变，所以**每轮都要重新查**。

> **卡片推进方式**（实测）：
> - 处理完一张 → 返回列表 → **慢速拖拽**推进下一张：
>   ```bash
>   "$ADB" shell input swipe 540 1600 540 1100 1000     # 500px / 1000ms
>   ```
> - 该拖拽**恰好推进 1 张卡**（连测 2 次稳定：上一张滚出、下一张上位）。
> - ❌ **不要用快速滑**（如 400ms）：会因**惯性 fling 跳 2–3 张**。
> - 卡片高约 **517–533px**；慢拖每张会**轻微漂移 ~40px**，故**不能死用固定坐标** —— 拖完**重新 dump 取第一张完整卡**再点，开卡后核对岗位名。

**验证**：前台 Activity 变为职位详情页。

```bash
adb shell dumpsys activity activities | grep ResumedActivity
# 期望 com.hpbr.bosszhipin/.geekjd.activity.BossJobPagerActivity
```

> ⚠️ **开卡后必须核对岗位名**：读 `tv_job_name`，确认点开的正是目标卡。实测发生过**坐标漂移点错卡**（点到上一张已处理的卡）。列表滚动后坐标会变，每轮都要重新取坐标 + 开卡后核对。

**预期结果**：进入职位详情页（岗位名 / 薪资 / 招聘者 / 职位详情 / 底部「立即沟通」按钮）。

> ⚠️ **坑：首次进入会弹引导浮层**
> 首次打开职位详情时会弹出 PopupWindow 引导（「标记不合适、举报」+「左右滑动，可切换职位」），会拦截点击。点一下空白处关掉即可：
> ```bash
> adb shell input tap 540 948
> ```

**职位卡片内部元素 id**（备查，用于读列表、做列表层红线筛）：

| 内容 | resource-id |
|---|---|
| 岗位名称 | `com.hpbr.bosszhipin:id/tv_position_name` |
| 薪资 | `com.hpbr.bosszhipin:id/tv_salary_statue` |
| 公司名 | `com.hpbr.bosszhipin:id/tv_company_name` |
| 融资阶段 | `com.hpbr.bosszhipin:id/tv_stage` |
| 公司规模 | `com.hpbr.bosszhipin:id/tv_scale` |
| 招聘者 | `com.hpbr.bosszhipin:id/tv_employer` |
| 活跃状态 | `com.hpbr.bosszhipin:id/tv_active_status` |
| 地点 | `com.hpbr.bosszhipin:id/tv_distance` |
| 卡片底部标记 | `com.hpbr.bosszhipin:id/bottom_reason_tv` |

### 4-B 读取当前页面的 JD

**目标**：读取当前职位详情页的完整 JD 正文。

**操作**：

```bash
bash tools/read_jd.sh          # 打印岗位/薪资/公司 + 完整 JD
```

它内部会：滚到页面顶部读头部字段 → 下滑到 JD 块 → **展开末尾的「查看更多」** → 打印正文。带 `-v/-r` 时顺带写入记录。

**⚠️ 坑：JD 默认是折叠的**
未展开时，`tv_description` 的文本末尾带「**查看更多**」，只到第 4 条就截断。要拿完整 JD 必须先展开：

1. **先下滑页面**，让「查看更多」进入可点区域；
2. 点「查看更多」：

```bash
adb shell input tap 873 950
```

⚠️ 点击坐标**必须落在 `tv_description` 节点 bounds 内**。实测节点底部为 `y=982`，点 `y=998`（超出节点）无效，`y≈950` 有效。（`read_jd.sh` 是按 description 的 bounds 现算落点的，手工点才需要自己注意。）

**职位详情页字段 id**（备查）：

| 内容 | resource-id |
|---|---|
| 岗位名称 | `com.hpbr.bosszhipin:id/tv_job_name` |
| 薪资 | `com.hpbr.bosszhipin:id/tv_job_salary` |
| 地点 | `com.hpbr.bosszhipin:id/tv_required_location` |
| 经验 | `com.hpbr.bosszhipin:id/tv_required_work_exp` |
| 学历 | `com.hpbr.bosszhipin:id/tv_required_degree` |
| 招聘者 | `com.hpbr.bosszhipin:id/tv_boss_name` |
| 招聘者头衔 | `com.hpbr.bosszhipin:id/tv_boss_title` |
| 活跃标签 | `com.hpbr.bosszhipin:id/boss_label_tv` |
| **JD 正文** | `com.hpbr.bosszhipin:id/tv_description` |

### 4-C 判断 JD 与简历的适配度

**目标**：针对当前 JD，对照简历打 0–100 适配度分，决定是否投递。

**评定标准**：[投递标准.md](templates/投递标准.md) —— 自己填一份放到仓库根目录。

**输入**：

| 输入 | 位置 |
|---|---|
| 当前 JD 正文 | 见 4-B（`tv_description`） |
| 我的简历 | [简历.md](templates/简历.md) |
| 评定标准 | [投递标准.md](templates/投递标准.md) |

#### 判定规则

**第 1 步 · 列表层红线筛**（不必开卡；列表卡已显示 薪资 `tv_salary_statue` / 城市 `tv_distance` / 公司 `tv_company_name` / 招聘者 `tv_employer`）

命中任一条 → **否**。红线写在自己的投递标准里，典型是：

| # | 红线 |
|---|---|
| 1 | 明确不投的公司 / 行业 / 关联公司 |
| 2 | 外包（人力 / 项目外包、劳务派遣、代招、驻场） |
| 3 | 猎头 / 人才服务 / 人力资源 / 第三方代招 |
| 4 | 不投的地域 |
| 5 | 非全职（实习 / 兼职 / 合同工） |

**第 2 步 · 读 JD 后判定**（必须先开卡读到 JD 正文）：

| # | 否决项 |
|---|---|
| 1 | **学历门槛（只有写死的才算）**：JD 写「985/211 **必须** / **不用投** / 一本以下不要」；写「985/211 **优先**」**不算门槛，照投** |
| 2 | **必备技能缺失**：JD 写「必备/必须/要求」的核心技能，简历完全没有 |
| 3 | **小公司 + 工资太低** |
| 4 | 方向 / 语言栈不符（例：主力语言不对） |

**其余 → 按「能不能胜任」判**（默认口径，按自己情况改）：

- **核心就一条：我能不能胜任** —— 技术能胜任 → **投**；
- **方向不必完全对口**（相邻方向的开发岗也投）；
- **扣分只认硬门槛**：只认「**必备 / 必须 / 要求 / 需具备**」；「**加分项 / 优先 / 了解 / 熟悉**」**一律不扣分**；
- **年限不否决**（1-3 年 / 3-5 年都算）；
- **薪资不设上限**；**不单看薪资否决** —— 只有「小公司 + 低薪」组合才否。

**输出要求**：每张必须给出「**判定（投 / 否）+ 理由**」，理由要落到 JD 里具体的字句上，并落盘到 [投递记录.md](templates/投递记录.md)。

> 判否也要写理由 —— 否则事后复盘时分不清「当时为什么没投」。

#### 结果分支

| 判定 | 动作 |
|---|---|
| ✅ **投** | 进入 **4-D** 点「立即沟通」→ 聊天页；之后**返回两次**（聊天页 → 详情页 → 列表） |
| ❌ **否** | **返回一次**（详情页 → 列表），跳过该职位 |

> 两条分支最终都回到**职位列表**，再进入下一轮循环。

**写记录**（在详情页执行；`-v 投` / `-v 否`）：

```bash
bash tools/read_jd.sh -v 投 -r "理由…"
```

> ⚠️ **公司名从哪来**：`read_jd.sh` 优先取 `tools/.last_company`（`next_card.sh` 每次选中卡时写进去的列表页公司名）。因为**部分职位详情页没有招聘者行**，从详情页取不到公司名 —— 取空了去重就会失效、同一张卡反复出现。所以**卡一定要用 `next_card.sh` 找**，那条链不能断。

### 4-D 点击「立即沟通」

**目标**：与当前职位的招聘者发起沟通。

**操作**：点击底部「立即沟通」

```bash
adb shell input tap 540 2255
```

**元素定位**：

| 项 | 值 |
|---|---|
| 按钮 | `com.hpbr.bosszhipin:id/btn_chat` |
| bounds | `[69,2194][1011,2315]` |
| 点击坐标（中心） | `540, 2255` |

**验证**：前台 Activity 变为聊天页。

```bash
adb shell dumpsys activity activities | grep ResumedActivity
# 期望 com.hpbr.bosszhipin/.chat.single.activity.ChatRoomActivity
```

**⚠️ 关键行为：点击即自动发送招呼语**
点「立即沟通」不只是打开聊天页 —— 会**立即以你的名义发出一条招呼语**（取自你的常用语），状态显示「送达」。**这是一条真发给 HR 的消息，发出后不可撤回。**

**聊天页（ChatRoomActivity）元素 id**：

| 元素 | resource-id | 坐标（中心） |
|---|---|---|
| 左上返回 | `com.hpbr.bosszhipin:id/iv_back` | `82, 163` |
| 招聘者名 | `com.hpbr.bosszhipin:id/tv_title` | — |
| 招聘者头衔 | `com.hpbr.bosszhipin:id/tv_sub_title` | — |
| 输入框 | `com.hpbr.bosszhipin:id/editText_with_scrollbar` | `483, 2278` |
| 右上「⋯」 | `com.hpbr.bosszhipin:id/iv_action_2` | `992, 163` |

**返回路径**（实测）：

| 当前位置 | 操作 | 到达 |
|---|---|---|
| 聊天页 `ChatRoomActivity` | 点左上 `iv_back` `(82,163)` | 职位详情页 `BossJobPagerActivity` |
| 职位详情页 `BossJobPagerActivity` | 点左上 `iv_back` `(99,152)` | 职位列表 `MainActivity` |

> 循环处理一个职位后，需连点两次返回（聊天页 → 详情页 → 列表）才能回到岗位列表。

**副发现：重复沟通不会重复发消息**
对**已沟通过**的职位再次点「立即沟通」，**只打开已有会话、不重复发送招呼语**。即自动招呼语仅在**首次**沟通时发出。

---

## 恢复用操作手册

> 上下文清空后照这个接着跑即可。所有状态都在文件里，不依赖对话记忆。

**每张卡两步：**

**① 找卡 + 开卡 + 读 JD**

```bash
cd <skill 目录>
export ADB="<你的 adb 路径>"; export MSYS_NO_PATHCONV=1
OUT=NONE
for i in 1 2 3 4 5 6; do OUT=$(bash tools/next_card.sh); [ "$OUT" != "NONE" ] && break; "$ADB" shell input swipe 540 1600 540 1000 900 >/dev/null 2>&1; sleep 2; done
set -- $OUT; "$ADB" shell input tap "$1" "$2"; sleep 3
bash tools/read_jd.sh          # 打印岗位/薪资/公司 + 完整 JD
```

**② 判定 → 记录 → 投或返回**

```bash
bash tools/read_jd.sh -v 投 -r "理由"       # 或 -v 否 -r "理由"（自动写入 投递记录.md）
# 投：立即沟通 → 聊天页返回 → 详情页返回
"$ADB" shell input tap 540 2255; sleep 3
"$ADB" shell input tap 82 163; sleep 2
"$ADB" shell input tap 99 152; sleep 3
# 否：详情页返回一次
"$ADB" shell input tap 99 152; sleep 3
```

**工具**：

- `tools/next_card.sh` —— 列表页找「第一张未处理卡」（按公司名比对 [投递记录.md](templates/投递记录.md)），输出 `x y 公司`
- `tools/read_jd.sh` —— 读 JD + 展开「查看更多」，带 `-v/-r` 时写入记录
- `tools/cards.ps1` / `tools/extract_jd.ps1` —— 解析 UI dump（PowerShell）
- `tools/.last_company` —— `next_card.sh` 每次把选中卡的公司名写这里；`read_jd.sh` 写记录时优先用它做「公司」字段。修的是这个 bug：部分职位详情页没有招聘者行，原来写出的公司为空，导致 `next_card.sh` 认不出已处理、反复返回同一张卡

**注意事项**：

- 推荐流刷到底（`next_card.sh` 连拖 6 次仍返回 `NONE`）→ 换关键词搜索继续，或收工
- 卡推进用**慢拖 500px/1000ms**；快滑会惯性跳 2–3 张
- 开卡后**必须核对岗位名**，防止坐标漂移点错
- 已沟通的职位不会从列表消失，靠 `next_card.sh` 去重
- **打招呼不可撤回**：执行前确认判定结论，一次只点一条
- 连续 3 次定位 / 读页失败，或遇到未知弹窗 → 停手交给人工，不要硬试
- 出现静默触顶（按钮没变化但没发出去）→ 立刻停，不要重试
- 平台规则会变：**慢一点、少一点、每条都真读**，是这套流程能长期跑下去的前提

---

## 装到 Claude Code 里

把整个目录拷到 `~/.claude/skills/boss-zhipin-autopilot/`（个人级）或项目里的 `.claude/skills/`（项目级），Claude Code 启动时会自动发现。之后直接说「用 BOSS 直聘投递流程接着跑」即可。

## 目录

```
SKILL.md                  # 你正在读的这份（工作流本体）
README.md                 # 面向 GitHub 的说明
tools/next_card.sh        # 找下一张未处理卡（去重 + 翻页）
tools/read_jd.sh          # 读 JD + 展开「查看更多」+ 写记录
tools/cards.ps1           # 解析列表页 UI dump
tools/extract_jd.ps1      # 解析详情页 UI dump
templates/投递标准.md      # 判定标准的模板，改成你自己的
templates/简历.md          # 简历基准模板
templates/投递记录.md      # 记录表模板
```
