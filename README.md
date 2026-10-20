# 祀 · 终末地桌宠

一个帮你盯 C 语言编译的桌面宠物。她会在你写错的时候吐槽并指出原因，记住你常犯的错，
根据互动积累好感度，每天给你三道题。

> 角色「祀」来自《明日方舟：终末地》。本项目是非官方二次创作，**不含任何官方美术资源**，
> 立绘素材由使用者自行提供。

## 作者 / 许可

| 项目 | 内容 |
|---|---|
| 作者 | **taoyu188** |
| 代码许可 | [MIT](LICENSE) —— 可自由使用、修改、分发、商用，**但必须保留版权声明与许可文本** |
| 角色与素材 | 「祀」及《明日方舟：终末地》相关版权归**上海鹰角网络**；本仓库不含其美术资源 |

### 二次分发时请保留

1. `LICENSE` 文件（MIT 要求）
2. `NOTICE.md` 里的第三方声明
3. README 里的作者与仓库链接

想把本项目改造成自己的桌宠没问题——换个角色包、改掉台词，
但请保留上述声明，并在 README 里注明「基于 taoyu188/siqu 修改」。
## 一键使用

**双击 `start.cmd`** 就行。它会自动：

1. 检查 Node.js（没有就提示下载地址）
2. 绕过 PowerShell 执行策略限制
3. 启动桌宠

前提只有一个：**装了 Node.js 18+**（[nodejs.org](https://nodejs.org/)）。

> 不加 `start.cmd` 也可以，直接跑：
> ```powershell
> powershell -ExecutionPolicy Bypass -File .\Start-Siqu.ps1
> ```

桌宠起来后**右键点她**就是全部功能入口。
## 快速开始（拿到仓库之后）

需要：**Windows 10/11** + **Node.js 18+**（`node -v` 能出版本号即可）。
PowerShell 建议 5.1 以上（系统自带）。

```powershell
# 1. 进来
cd siqu

# 2. 先切到占位角色（仓库不含立绘素材，见下方「素材说明」）
node .\tools\character.js --use placeholder

# 3. 启动
powershell -ExecutionPolicy Bypass -File .\Start-Siqu.ps1
```

启动后**右键点她**就是全部功能入口。

> 想换成自己的角色？见「换角色（立绘 / 语音）」一节。

### 素材说明

仓库**不含**任何游戏立绘与语音——那些版权属于原作者。仓库里只有一套
程序生成的**占位角色**（`characters/placeholder/`），够你把功能跑起来。
自己的立绘放进去即可，`assets/` 和 `characters/*/images/` 已在 `.gitignore` 里。

## 位置

| 项目 | 路径 |
|---|---|
| 程序目录 | `siqu\`（仓库根） |
| 启动脚本 | `siqu\Start-Siqu.ps1` |
| 运行数据 | `%USERPROFILE%\.siqu`（日志、人格状态、错题库、答题记录、森空岛凭据） |

## 怎么启动

- **桌面「祀 桌宠」** —— 手动启动（也可直接跑 `Start-Siqu.ps1`）
- **开机自启**：`%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\祀 桌宠（开机自启）.lnk`
  （不想自启就删掉这个快捷方式）
- 桌面还有：**祀 诊断自检**、**Python**
- 其余功能（今日三题 / 终末地日程 / 状态面板 / 台词库 / 森空岛登录）都在**桌宠右键菜单**里

## 目录结构

```
siqu/
├─ wpf/
│  ├─ Pet.ps1            主程序：透明窗口 + 表情 + 气泡 + 事件监听
│  ├─ PersonaPanel.ps1   状态面板：好感度 / 心情 / 曲线 / 记忆
│  ├─ QuizPanel.ps1      今日三题
│  └─ PersonaLines.ps1   台词库可视化编辑
├─ core/
│  ├─ diagnose.js        编译报错诊断（规则匹配）
│  ├─ rules.json         规则库（21 条）
│  ├─ errorbook.js       错题库（规则没认出的错自动记录 + 重复识别）
│  ├─ codeaware.js       看懂源码（在程序里叫她就回应）
│  ├─ persona.js         人格引擎（8 心情 / 5 等级 / 记忆 / 撤回）
│  ├─ crashinfo.ps1      运行时崩溃解析（读 Windows 事件日志）
│  ├─ daily.js           每日三题调度 + 间隔重复
│  └─ questions.json     题库（96 道）
├─ persona/persona.json  台词库（也可用「祀 台词库」界面改）
├─ roles/
│  ├─ roles.json         角色注册表（图片 / 语音 / 台词库）
│  └─ active.txt         当前角色（本地覆盖，不进 git）
├─ characters/           角色包：<id>/images/<state>.png + <id>/audio/
│  └─ placeholder/       程序生成的占位角色（可随仓库分发）
├─ assets/
│  ├─ siqu-<state>.png   自己的立绘（不进 git）
│  └─ audio/             自己的语音（不进 git）
├─ build/gcc-shim.exe    编译器包装器（Dev-C++ 指向它）
└─ tools/
   ├─ character.js       角色包管理（换图换声）
   ├─ make-placeholder.js 生成占位立绘
   ├─ merge-questions.js / verify-questions.js   题库合并与验证
   └─ errorbook-to-rules.js                      错题转规则
```

## 语音（点击专用）

点击她 → 说「呆货」→ 播放 `assets/audio/daigo.m4a`（2 秒语音）。

- **只在点击时触发**；编译报错时**不会**响（即使报错台词里也有"呆货"）
  —— 播放函数只挂在点击处理器上，报错路径不调用它
- 启动时预加载，第一次点击也不卡；连点会从头重放
- 支持 `.wav`（SoundPlayer）和 `.m4a/.mp3`（MediaPlayer，WPF 内置解码）
- 换音频：把文件放进 `assets/audio/`，改 `persona.json` 里的
  `audio.daigo.file` 即可，**不用动代码**
- `assets/audio/daigo-placeholder.wav` 是早前的占位提示音，可以删

自测：

```powershell
powershell -ExecutionPolicy Bypass -File D:\Projects\siqu\wpf\Pet.ps1 -TestAudio
# 日志里应出现两行：case A → audio: played (.m4a)；case B 不播放
```

## 台词库可视化

桌面「**祀 台词库**」或：

```powershell
powershell -ExecutionPolicy Bypass -File D:\Projects\siqu\wpf\PersonaLines.ps1
```

- 左侧列出所有台词池（中文名 + 条数），右侧一行一条编辑
- **保存前自动备份** `persona.json.bak-时间戳`；JSON 校验不过不会写坏原文件
- 可以「新增台词池」——为以后加新触发场景留的口子（新池要生效需在
  `core/persona.js` 里加一个事件分支引用它）

## 错题库 → 规则库

规则没认出来的错误会进错题库，出现次数攒起来之后可以转成正式规则：

```powershell
cd D:\Projects\siqu

# 看有哪些待转化（会告诉你是否已被现有规则覆盖）
node .\tools\errorbook-to-rules.js --list

# 生成规则草稿到 core\rules-draft.json
node .\tools\errorbook-to-rules.js --draft

# 补完字段后启用某一条（自动标记该错误为"已认识"）
node .\tools\errorbook-to-rules.js --add 1 --id my-rule `
  --title "标题" --why "原因" --fix "怎么改" --taunt "她的一句话"

# 新加了规则后，把"现在已被覆盖"的旧条目批量标记为已认识
node .\tools\errorbook-to-rules.js --sync
```

## 答题会影响力好感度

在「今日三题」里答对 +1.5、答错 −0.5，并同步切换她的心情（满意 / 困惑）。
所以刷题不只是刷题，她也在看。

## 终末地日程

桌面「**祀 终末地日程**」，或：

```powershell
powershell -ExecutionPolicy Bypass -File D:\Projects\siqu\wpf\SchedulePanel.ps1

# 或者纯命令行
cd D:\Projects\siqu
node .\core\schedule.js --now                 # 看日程
node .\core\schedule.js --done d2             # 勾一条
node .\core\schedule.js --check-all daily     # 一键全勾
node .\core\schedule.js --snapshot 180        # 记录理智快照
```

**数据来自森空岛实时接口**（扫码登录一次即可），没登录时退回本地推算。

| 功能 | 说明 |
|---|---|
| 每日重置倒计时 | 04:00（官方 2026-03-25 起生效） |
| 每周重置倒计时 | 周一 04:00（`_verify` 标记为待确认） |
| 任务清单 | 每日 5 条、每周 2 条，**按游戏日/游戏周自动重置** |
| 理智推算 | 记录一次快照，之后按恢复速度往后算，封顶 |
| 主动提醒 | 重置前 60 分钟若有未完成任务 → 她会说；理智 ≥80% → 也会说 |

配置在 `game/schedule.json`：

```json
"stamina": { "unit": "理智", "max": 240, "recoverMinutes": 6, "_verify": true }
```

`_verify: true` 表示这个数值还没官方确认——**按你游戏里的实际数值改**，改完把
`_verify` 改成 `false`，界面底部的提示就会消失。

任务清单也是这里改（增删 `tasks.daily` / `tasks.weekly` 里的条目，`id` 不要重复）。

## 森空岛接入（读取真实游戏数据）

桌面「**祀 森空岛登录**」或：

```powershell
cd D:\Projects\siqu
node .\core\skland.js --qr            # 扫码登录（会弹出二维码图片）
node .\core\skland.js --bindings      # 看绑定角色
node .\core\skland.js --endfield      # 读终末地数据
node .\core\skland.js --status        # 凭据状态
node .\core\skland.js --logout        # 删除本地凭据
```

| 项目 | 说明 |
|---|---|
| 保存什么 | **只存 token 和 cred**，密码用完即弃 |
| 位置 | `%USERPROFILE%\.siqu\skland.json` |
| 权限 | **只读**：查数据，不签到、不领奖、不改账号 |
| 缓存 | 实时数据缓存 2 分钟，避免频繁请求 |

能读到：**理智（当前/上限/回满时间）**、每日活跃度、每周进度、角色等级/世界等级。

多个终末地账号用 `--uid` / `--role` / `--server` 选择，`--pick <roleId>` 设默认。

实测数值（可写进 `game/schedule.json` 校准）：
- 理智上限 **360**，恢复 **7.2 分钟/点**（接口 curStamina/maxStamina/maxTs 反推）
## Python 支持

C 的报错靠 gcc-shim 拦截；Python 是**运行时**报错，所以换成"包一层运行器"。

**用法：正常写脚本，运行时前面加一层**

```powershell
cd D:\Projects\siqu
node .\core\pyrun.js 你的脚本.py          # 或者用封装好的
.\pyrun.cmd 你的脚本.py
```

跑完之后，桌宠会在 3 秒内发现 Traceback，说一句并给出解释（气泡里展开原因和改法）。

单独看诊断结果：

```powershell
node .\core\pydiag.js                 # 诊断最近一次运行
node .\core\pydiag.js --tail 3        # 往前第 3 次
node .\core\pydiag.js --json --out x.json
```

**能吃下的报错**（`core/py-rules.json`，16 条）：

NameError、UnboundLocalError、str+int 拼接、类型不符运算、缩进错误、语法错误、
下标越界、KeyError、除零、模块未安装、int() 转换失败、递归过深、
文件不存在、None 上取属性、str 用 append、少传参数。

未命中的错误会走通用兜底（教你怎么读 Traceback）。

**加新规则**：在 `core/py-rules.json` 的 `rules` 里追加一条，
`pattern` 是对 `异常类型: 消息` 的正则，配好 `title / why / fix / taunt` 即可。

### 说明

- 只有**经过 pyrun 运行**的脚本才会被记录（直接在 IDLE 里跑不经过）
- 日志在 `%USERPROFILE%\.siqu\python.log`，会按次追加；清空它不影响桌宠
- 桌宠启动时会把当前日志长度当基线，历史错误不会重复吐槽
## 换角色（立绘 / 语音）

想让别人换个角色？不用改代码，一个命令的事。

```powershell
# 看有哪些角色、缺不缺图
node .\tools\character.js --list
node .\tools\character.js --check

# 切换（写 roles/active.txt，重启桌宠生效）
node .\tools\character.js --use placeholder
```

### 做一个新角色（三种方式）

**方式一：从零开始（用占位图打底，先跑起来再换图）**

```powershell
node .\tools\character.js --new nene --name 宁宁
# 然后替换 characters\nene\images\ 里的 8 张图
node .\tools\character.js --use nene
```

**方式二：已有 8 张表情图，直接导入**

把图片按状态命名后放进一个目录：

```
我的角色\
├─ idle.png      （待机）
├─ happy.png     （满意）
├─ taunt.png     （嫌弃）
├─ confused.png  （困惑）
├─ embarrassed.png（慌乱）
├─ jealous.png   （吃醋）
├─ pout.png      （赌气）
└─ sleep.png     （犯困）
```

```powershell
node .\tools\character.js --import "D:\我的角色" --id nene --name 宁宁 --audio "D:\声音.m4a"
node .\tools\character.js --use nene
```

缺的图会自动用占位图补上，所以只画 2~3 张也能先跑。

**方式三：手动改 `roles/roles.json`**

在 `roles` 数组里加一条，`images` 指向你的图，`audio.click` 指向语音文件。

### 换语音

```powershell
# 每次点击都播
node .\tools\character.js --set-audio nene --file "D:\声音.m4a"

# 只在台词里含某个词时播（比如"呆货"）
node .\tools\character.js --set-audio nene --file "D:\声音.m4a" --trigger 呆货

# 不要语音
node .\tools\character.js --clear-audio nene
```

支持 `.wav / .mp3 / .m4a / .ogg / .flac`。`.wav` 用 SoundPlayer，其余用 MediaPlayer（WPF 内置解码）。

### 图片要求

| 项目 | 建议 |
|---|---|
| 格式 | PNG 透明背景（JPG 也能跑，但没有透明边） |
| 尺寸 | 正方形，512×512 或更大 |
| 构图 | 角色底部贴近图片底边（桌宠按底部对齐） |
| 缺图 | 自动回退到 `idle.png` |

### 角色注册表结构

```json
{
  "id": "nene",
  "name": "宁宁",
  "scale": 1.0,
  "images": {
    "idle": "characters/nene/images/idle.png",
    "happy": "characters/nene/images/happy.png"
  },
  "audio": {
    "click": { "file": "characters/nene/audio/voice.m4a", "volume": 0.85, "triggerText": "" }
  },
  "persona": "persona/persona.json"
}
```

`scale` 会整体缩放桌宠；`persona` 可以指向另一个台词库文件，
这样一个角色可以配一套自己的说话风格。
## 参考的开源项目

做这个模块之前查了一圈社区实现，主要参考：

| 项目 | 用途 |
|---|---|
| [nonebot-plugin-skland](https://github.com/FrostN0v0/nonebot-plugin-skland) | 森空岛查游戏数据，**支持终末地**（Python, MIT） |
| [Skland_API](https://github.com/ProbiusOfficial/Skland_API) | 森空岛 API 文档（鹰角 token → cred → 游戏数据） |
| [skland-daily-attendance](https://github.com/AEtherside/skland-daily-attendance) | 森空岛每日签到（TS） |
| [ok-end-field](https://github.com/AliceJump/ok-end-field) | 终末地自动化（Python, AGPL） |

**当前版本没有接入森空岛 API**——那需要你的鹰角账号凭证（token），有账号安全风险。
如果以后想要"真实理智/委托进度"，可以参照上面前两个项目做一个可选的登录模块；
在那之前，本模块用本地推算。

## Dev-C++ 接入

编译器路径被改成 `D:\Dev-Cpp\MinGW64\bin\gcc-shim.exe`（shim 会转发给真 gcc 并把报错写进日志）。

```powershell
cd D:\Projects\siqu
.\devcpp.ps1 -Status    # 看当前状态
.\devcpp.ps1 -Off       # 还原成原装 gcc
.\devcpp.ps1 -On        # 重新接入
```

shim 会自动给编译附加 `-std=gnu99 -Wall`（Dev-C++ 默认 gnu90，`for (int i...)` 会报错；
不开 -Wall，`scanf` 忘 `&` 会静默通过）。

## 常用命令

```powershell
cd D:\Projects\siqu

# 诊断自检（7 个用例）
powershell -ExecutionPolicy Bypass -File .\selftest.ps1

# 人格测试 / 重置
node .\core\persona.js --state
node .\core\persona.js --event called
node .\core\persona.js --reset
$env:SIQU_FAKE_HOUR=2; node .\core\persona.js --event idle   # 预览"犯困"

# 错题库
node .\core\errorbook.js --list
node .\core\errorbook.js --clear

# 每日三题
node .\core\daily.js --today
node .\core\daily.js --stats
node .\core\daily.js --reset

# 表情批量导入（换立绘用）
powershell -ExecutionPolicy Bypass -File .\tools\import-expressions.ps1

# 题目：合并新批次（先 --dry 校验结构）
node .\tools\merge-questions.js --file .\textbook\generated\batchN.json --dry
node .\tools\merge-questions.js --file .\textbook\generated\batchN.json

# 题目：编译并跑测试用例，验证编程题参考答案
node .\tools\verify-questions.js
```

## 题库

当前 **96 道**（选择题 79 / 编程题 17），覆盖教材第 1–14 章：

| 知识点 | 数量 | 知识点 | 数量 |
|---|---|---|---|
| 数组 / 指针 | 11 / 11 | 递归 | 10 |
| 循环 | 10 | 函数 / 文件 / 链表 | 6 / 6 / 6 |
| 运算符 / 预处理 | 5 / 5 | 分支 | 4 |
| 结构体 / 作用域 | 3 / 3 | 其余零散 | 各 1–2 |

**编程题都带 `tests` 字段**，`verify-questions.js` 会真的调 gcc 编译、跑每组输入、比对输出。
当前 17 道题共 47 组用例，全部通过。

### 加新题的流程

1. 写一个批次文件 `textbook/generated/batchN.json`（格式见现有批次）
2. `merge-questions.js --dry` 校验结构（id 冲突、选项数、答案解析）
3. `merge-questions.js` 写入题库
4. `verify-questions.js` 验证所有编程题

题库文件是 `core/questions.json`；答题记录在 `%USERPROFILE%\.siqu\questions-state.json`。

## 换表情图

1. 准备透明 PNG，**头顶对齐**、宽度接近、512 或更大
2. 放进 `assets/`，命名 `siqu-<state>.png`（state 见下表）
3. 改 `roles/roles.json` 里对应路径
4. 重启桌宠

| state | 情绪 | 触发 |
|---|---|---|
| idle | 待机 | 默认 |
| happy | 满意 | 编译通过 |
| taunt | 嫌弃 | 认识的报错 |
| confused | 困惑 | 没见过的错 / 警告 / 深夜 |
| embarrassed | 慌乱 | 你叫她名字 / 夸她 |
| jealous | 吃醋 | 20 分钟没点她且频繁编译（15 分钟冷却） |
| pout | 赌气 | 连点她 5 次 |
| sleep | 犯困 | 23:00–07:00 且无事件 |

## 故障排查

| 现象 | 看哪里 |
|---|---|
| 桌宠没反应 / 报错 | `%USERPROFILE%\.siqu\pet.log` |
| 编译报错她不说 | `%USERPROFILE%\.siqu\build.log` 有没有新记录 |
| 崩溃不提示 | 只在 Dev-C++ 的 ConsolePauser 运行时密集检测；直接双击 exe 最多延迟 60 秒 |
| 好感度不涨 | `node .\core\persona.js --state` 看文件是否在写 |

## 已知问题

- `siqu-sleep.png` 的原图**没有角**，和另外 7 张不一致，建议换图重跑导入脚本
- 只覆盖 C 文件；`.cpp` 走 `g++.exe`，没经过 shim
- 早期 Electron 版本已弃用（这台机器上 Chromium 起不来），代码还在旧副本 `siqu/app` 里
