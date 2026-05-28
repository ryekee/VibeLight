# VibeLight 设计文档

**日期**：2026-05-27
**状态**：草稿（待用户确认）
**作者**：通过 brainstorming 与 Carmela 协作产出

---

## 1. 目标

把 AI Agent 的工作状态投射到物理灯带上，让用户在屏幕之外也能感知 Agent 在做什么、是否需要介入。

**v1 范围**：

- 仅支持 Claude Code（Codex 推迟到 v2）
- 仅支持 Home Assistant 接入的灯具
- 仅 macOS（menubar 应用形态）

## 2. 状态模型

PRD 原有 6 个状态被精简为 7 个（合并思考 / 处理，新增 COMPACTING）：

| 状态 | 含义 | 颜色 | 效果 | 优先级 |
|---|---|---|---|---|
| `ERROR` | 工具调用出错 / Agent 报错 | 红 | 闪烁 1 Hz，持续 5 s 后自动转 IDLE | 5 |
| `NEEDS_AUTH` | Claude Code 在等待用户授权工具调用 | 红 | 常亮 | 4 |
| `WAITING_INPUT` | 其他类型的"等待用户" notification | 橙 | 闪 3 s 后转常亮 | 3 |
| `COMPACTING` | Claude Code 正在压缩上下文 | 黄 | 呼吸（2 s 周期） | 2.5 |
| `WORKING` | Agent 在工作（思考 + 工具调用合并） | 蓝 | 呼吸（2 s 周期） | 2 |
| `DONE` | Agent 刚完成一轮回复 | 紫 | 闪 2 s 后转 IDLE | 1 |
| `IDLE` | 无 session 活跃 / 等待新输入 | 紫 | 常亮 | 0 |

**设计说明：**

- 合并"思考中 / 正在处理"：Claude Code hooks 没有"模型正在出 token"事件，只有工具调用前后能插手，强行区分会很脆弱。
- `DONE` 与 `IDLE` 共用紫色：完成自然过渡到待机，避免颜色频繁切换造成的视觉噪声。
- `ERROR` 自动 5 s 后清除：避免"红色挂着不走"导致新旧错误难以区分。`NEEDS_AUTH` 不设 TTL，因为它真的需要用户处理。
- `COMPACTING` 是瞬时戳：`PreCompact` hook 进入该状态，下一个 `UserPromptSubmit` / `PreToolUse` / `PostToolUse` / `Stop` 中任一事件到来时清除并按该事件正常转移。

## 3. 架构

```
┌──────────────────┐    POST /event       ┌──────────────────────────┐
│ Claude Code      │ ──────────────────►  │   VibeLight.app          │
│ session (hook)   │                      │   (macOS menubar)        │       Home
└──────────────────┘                      │                          │       Assistant
┌──────────────────┐                      │  - HTTP broker (NWListener) │ ───► REST API ──► 灯带
│ Claude Code      │ ──────────────────►  │  - SessionStore + 仲裁      │
│ session (hook)   │                      │  - LightDriver              │
└──────────────────┘                      │  - HomeReachability         │
                                          │  - Onboarding UI            │
                                          │  - 菜单栏图标 + 菜单         │
                                          └──────────────────────────┘
```

### 3.1 组件职责

1. **Hook 脚本**（`~/.claude/hooks/vibelight.sh`）：极简 shell 脚本，把 hook payload 转发给本地 broker（`curl -m 0.2`），失败静默。
2. **HTTP broker**（VibeLight.app 内嵌）：监听 `127.0.0.1:17345`，接收 hook 事件，维护 session 状态表，做仲裁，调用 LightDriver。
3. **LightDriver**（protocol + HomeAssistantDriver 实现）：把抽象状态翻译为 HA service call。未来换生态只改这一层。
4. **HomeReachability**：用 NWPathMonitor + 周期性 HA `/api/` 探测判断是否"在家"。
5. **Menubar UI**：彩色圆点反映当前 effective_state；菜单提供 Pause、Test、Sessions、Settings、Quit。
6. **Onboarding**：首次启动引导用户完成 HA 连接、灯具选择、自动建 7 个 scene、家庭网络确认、Claude Code hooks 自动写入、灯效测试。

### 3.2 数据流

```
hook event → POST /event → EventRouter → SessionStore.apply(event)
                                       ↓
                                       Arbiter.compute() → effective_state
                                       ↓
                                       (if at home && not paused)
                                       ↓
                                       LightDriver.render(state) → HA scene.turn_on
                                       ↓
                                       MenuBarIcon.update(state)
```

## 4. Hook 事件到状态的转移

每个 session 是独立状态机。事件来自 Claude Code 的以下 hooks：

| Hook | 转移规则 |
|---|---|
| `SessionStart` | 注册 session，state = `IDLE` |
| `UserPromptSubmit` | → `WORKING` |
| `PreToolUse` | 保持 `WORKING`（不切换，避免抖动） |
| `PostToolUse` 且 `tool_response.is_error == true` | → `ERROR` |
| `PostToolUse` 正常 | 保持 `WORKING` |
| `Notification`（message 含 "permission" / "approve"） | → `NEEDS_AUTH` |
| `Notification`（其他） | → `WAITING_INPUT` |
| `PreCompact` | → `COMPACTING`；下次任何活动事件清除 |
| `Stop` | → `DONE`（2 s 后 → `IDLE`） |
| `SessionEnd` | 移除该 session |

**fallback 策略**：如果 `Notification.message` 文本匹配不可靠，统一按 `NEEDS_AUTH`（红色更安全 —— 都需要用户看屏幕）。

## 5. 多 session 仲裁

Broker 内存中维护：

```
sessions: Map<session_id, { state, since, cwd }>
```

每次事件后重算：

```
effective_state = sessions.values()
                 .map(s -> s.state)
                 .maxBy(priority, tieBreaker = mostRecent)
```

**僵尸 session**：5 分钟没收到任何事件的 session 自动转 IDLE 并从表中淘汰。

**ERROR 自动清除**：进入 ERROR 后 5 s 自动转 IDLE（每个 session 独立 timer）。若 5 s 内有新事件到达，timer 取消并按新事件正常转移（例如 `PreToolUse` → `WORKING`、`Stop` → `DONE`）。设计意图：避免红色挂着不走，但不阻止 session 真实活动的状态反映。

## 6. VibeLight.app

### 6.1 形态

- SwiftUI menubar 应用，macOS 13+
- 单个 `.app` 包，无外部依赖
- 开机自启（Login Item）

### 6.2 菜单

```
[colored dot] State summary — session abc-123 (~/repo-a)
─────────────────────────────────────
✓ Active (on home network)
  Pause for 30 minutes
  Pause for 1 hour
  Pause until tomorrow
─────────────────────────────────────
  Test light effect           ▶ (子菜单：依次 trigger 每个状态)
  Show sessions...
  Settings...
─────────────────────────────────────
  Quit VibeLight
```

### 6.3 Onboarding 流程

1. 欢迎页
2. HA 连接：mDNS 自动扫描 LAN 内 HA 实例并列出（点击直接填入），同时支持手动输入 URL；填入 Long-Lived Access Token，"Test connection" 按钮验证
3. 灯具选择：自动列出 `light.*` entity，dropdown 选一个
4. 家庭网络确认：检测当前 HA 可达性，记录 SSID（仅作 hint 显示，不作判定依据）
5. Claude Code 集成：一键写入 `~/.claude/settings.json` 的 hooks 配置 + 部署 `vibelight.sh`
6. 灯效测试：依次点亮 7 种状态（默认 Broker-emulated 模式），让用户确认
7. 完成页：提示"想要更顺滑的本地效果？随时去 Settings → Light → 升级到 Scene 模式"

**关键差异**：onboarding 不再自动建 scene。用户首次启动就能用，零 HA 端配置。Scene 模式是后续可选升级，从 Settings 里手动触发。

### 6.4 Settings 窗口

分 6 个 tab：

#### General
- Launch at login（toggle，默认开）
- Show notifications on HA errors（toggle，默认开）

#### Home Assistant
- **URL**（顶部是 LAN 扫描区 + 手动输入框）：
  - "Scan local network" 按钮：用 mDNS / Bonjour 浏览 `_home-assistant._tcp.local`，扫描结果以 list 展示（名称 + IP:port），点击即填入下方 URL 框
  - 进入 tab 时默认自动扫一次（200 ms 延迟，不阻塞 UI），同时支持手动 "Rescan"
  - 手动 URL 文本框作为 fallback，扫不到或用户用反向代理 / 公网域名时可直接输入
  - "Test" 按钮验证连通性
- Access Token（密码框 + "Replace" 按钮；存 Keychain，UI 不回显原文）
- Light entity（dropdown，"Refresh list" 按钮重新拉 entity 列表）
- **Light effect mode**（radio）：
  - **Broker-emulated**（默认）：broker 通过 REST 实时驱动颜色 / 亮度 / transition，无需 HA 端配置
  - **Scene pack**：使用预装的 7 个 `scene.vibelight_*`，broker 只发 `scene.turn_on`
  - "Install scene pack" 按钮：一键在 HA 中创建 7 个 scene（切到 Scene pack 模式时引导，也可独立点）
  - "Uninstall scene pack" 按钮：删除 HA 端的 vibelight scene

#### Colors & Effects
- 7 个状态的颜色 / 亮度 / 效果一览（每行：色块 + 颜色编辑器 + 亮度 slider + 效果下拉）
- "Reset to defaults" 按钮
- 注：Scene pack 模式下编辑这里需要重新 "Install scene pack" 才生效；Broker-emulated 模式下立即生效

#### Network
- 当前状态：`At home` / `Away`（实时）
- 上次检测到的家庭网络 SSID（hint）
- "Check now" 按钮
- HA reachability 探测间隔（默认 5 分钟，advanced）

#### Claude Code
- Hook 安装状态：`Installed ✓` / `Not installed`（v1 简化：比对 hook 文件存在性即可；v2 再做 hash 校验区分 "Out of date"）
- "Reinstall hooks" 按钮
- "Uninstall hooks" 按钮
- Hook 脚本路径展示（点击可在 Finder 中显示）

#### Advanced
- Broker 端口（默认 17345，改完需重启 app）
- 默认 Pause 时长（30 min / 1 h / Until tomorrow，选一个作为快捷默认）
- "Open logs folder" 按钮
- "Reset all settings" 按钮（确认对话框，会清 Keychain 和 UserDefaults）
- About：版本号、许可证、源码链接

### 6.5 "在家"检测（方案 C 混合）

- **NWPathMonitor** 监听网络变化（无需任何权限）
- 网络变化触发时 + 启动时 + 每 5 分钟周期性，向 HA 发 `GET /api/`（200 ms 超时）
- 可达 → "at home"；不可达 → "away"
- 记录 SSID 仅作 UI 展示用（"You're on home Wi-Fi: MyHome-5G"）

### 6.6 Pause

- 临时静音：30 min / 1 h / Until tomorrow
- Pause 期间：菜单栏图标仍然更新反映 Agent 状态，但**不向 HA 发送任何请求**
- 时间到自动恢复，菜单显示倒计时

## 7. Home Assistant 集成

### 7.1 通信方式

REST API（非 WebSocket）—— 事件驱动，状态变化时才发 1 个 service call，无需长连接。

### 7.2 渲染策略（双模式）

v1 同时实现两种灯效模式，用户可在 Settings 切换。**默认 Broker-emulated**，零 HA 端配置就能用；想要更平滑、流量更小的体验时升级到 Scene pack。

#### 7.2.1 Broker-emulated 模式（默认）

broker 通过 HA REST API 直接驱动灯具：

- 常亮：单次 `light.turn_on`，带 `rgb_color` + `brightness`
- 呼吸：周期性 `light.turn_on`，利用 HA 的 `transition` 参数让 HA 端做平滑过渡。例如 2 s 周期 → broker 每秒发 1 次，alternate 高/低亮度，`transition: 1`
- 闪烁：周期性 `light.turn_on`，`transition: 0`，alternate on/off

**流量估算**：呼吸状态约 1 call/s；闪烁状态约 2 call/s；ERROR 持续 5 s 闪后回 IDLE。可接受。

**优点**：HA 端零配置，颜色/亮度在 app 内即改即生效，新用户开箱即用。

**缺点**：网络流量高于 scene 模式；HA log 有可见的频繁 service call；HA 不可达时灯只能停在最后一次成功的状态。

#### 7.2.2 Scene pack 模式（可选升级）

- 用户在 Settings → Home Assistant → "Install scene pack" 后，VibeLight 通过 HA REST API（`/api/config/scene/config/*`）创建 7 个 scene：`scene.vibelight_idle` / `vibelight_working` / `vibelight_compacting` / `vibelight_waiting_input` / `vibelight_needs_auth` / `vibelight_error` / `vibelight_done`
- broker 状态变化时只调 `POST /api/services/scene/turn_on`，1 次切换
- 呼吸 / 闪烁等动态效果由灯具自带 effect 实现（HA scene 内 `effect: ...` 字段）或在 HA 端用 automation 实现
- 切换到此模式时如未安装 scene，强制弹安装引导

**优点**：流量极低；HA 不可达时灯能维持最后一个 scene；用户可在 HA UI 二次调整效果（保留高级用户的自定义空间）。

**缺点**：在 app 内改颜色 / 亮度后需重新 "Install scene pack"；灯具 effect 能力跨品牌差异大，某些灯具呼吸效果可能要在 HA automation 里手搓。

### 7.3 LightDriver 抽象

```swift
protocol LightDriver {
    func render(_ state: EffectiveState) async throws
    func cancel() async  // 切状态时取消当前进行中的效果循环
}

final class BrokerEmulatedDriver: LightDriver {
    let haClient: HAClient
    let lightEntityId: String
    private var effectTask: Task<Void, Never>?

    func render(_ state: EffectiveState) async throws {
        await cancel()
        // 按 state.effect 启动周期性 light.turn_on 循环
    }

    func cancel() async { effectTask?.cancel() }
}

final class ScenePackDriver: LightDriver {
    let haClient: HAClient

    func render(_ state: EffectiveState) async throws {
        try await haClient.callService(
            domain: "scene", service: "turn_on",
            entityId: "scene.vibelight_\(state.name.lowercased())"
        )
    }

    func cancel() async {}  // scene 模式无 broker 端循环
}
```

App 启动时根据 Settings 实例化对应 driver。切换模式无需重启 app（broker 内重建 driver 即可）。

未来支持其他生态时只新增 driver 实现，状态机 / 仲裁 / Settings UI 全部复用。

## 8. HTTP API

VibeLight.app 内嵌 HTTP server，监听 `127.0.0.1:17345`：

| Method | Path | 用途 |
|---|---|---|
| `POST` | `/event` | hook 上报事件 `{session_id, hook, payload}` |
| `GET` | `/state` | 当前所有 session 状态 + effective_state（调试 / Show sessions 窗口） |
| `POST` | `/test` | 手动触发某个状态（菜单 Test light effect 用） |
| `POST` | `/reload` | 重读配置 |
| `GET` | `/health` | 健康检查 |

仅监听 loopback，不暴露到网络。

## 9. Hook 部署

`~/.claude/hooks/vibelight.sh`：

```bash
#!/usr/bin/env bash
exec curl -s -m 0.2 -X POST \
  -H 'Content-Type: application/json' \
  --data-binary @- \
  "http://127.0.0.1:17345/event?hook=$1" >/dev/null 2>&1 || true
```

`~/.claude/settings.json` 的 `hooks` 段写入 8 个事件，全部指向 `vibelight.sh`，参数区分事件类型：`SessionStart` / `UserPromptSubmit` / `PreToolUse` / `PostToolUse` / `Notification` / `PreCompact` / `Stop` / `SessionEnd`。

VibeLight.app 提供"Reinstall hooks"按钮，便于升级时更新。

## 10. 失败模式

**核心原则**：VibeLight 出任何问题都不能阻塞 Claude Code。

| 场景 | 行为 |
|---|---|
| Broker 没起来 | hook `curl -m 0.2` 失败 → 静默 |
| HA 不响应 | 重试 1 次（500 ms 后），失败则记 log，状态表照常更新，下次状态变化重新尝试 |
| 不在家 | 状态表正常，菜单图标正常，**不发 HA 请求** |
| Pause 期间 | 同上 |
| HA token 过期（401） | 菜单图标加红色警告角标 + 通知中心弹一次提醒 |
| 配置损坏 | 启动时检测，弹 onboarding 重配 |
| 事件风暴（多 session 频繁切换） | broker 端 100 ms 去抖：状态在 100 ms 内反复变只发最后一个 service call |

## 11. 可观察性

- **菜单 → Show sessions**：窗口列出每个活动 session 的 `id / cwd / state / since`，实时刷新
- **菜单 → View logs**：打开 `~/Library/Logs/VibeLight/broker.log`
- 日志：os.Logger（系统日志） + 文件输出，按天滚动，保留 30 天

## 12. 项目结构

```
VibeLight/
├── prd.md
├── docs/superpowers/specs/2026-05-27-vibelight-design.md
├── VibeLight.xcodeproj
├── Sources/
│   ├── App/                       # SwiftUI 入口、AppDelegate、MenuBarController
│   ├── Broker/
│   │   ├── HTTPListener.swift     # NWListener + 极简 HTTP parser
│   │   ├── EventRouter.swift      # POST /event 路由
│   │   ├── SessionStore.swift     # 内存 session 表 + TTL
│   │   └── Arbiter.swift          # 仲裁 → effective_state
│   ├── StateMachine/
│   │   ├── State.swift            # 7 个状态 + 颜色 / 效果元数据
│   │   └── Transitions.swift      # hook 事件 → 状态转移
│   ├── Light/
│   │   ├── LightDriver.swift          # protocol
│   │   ├── BrokerEmulatedDriver.swift # 默认模式：REST 实时驱动
│   │   ├── ScenePackDriver.swift      # scene.turn_on 模式
│   │   └── ScenePackInstaller.swift   # 在 HA 中创建 / 删除 7 个 scene
│   ├── Network/
│   │   ├── HomeReachability.swift # NWPathMonitor + HA ping
│   │   ├── HADiscovery.swift      # NWBrowser mDNS 扫描 _home-assistant._tcp
│   │   └── HAClient.swift
│   ├── Onboarding/                # SwiftUI 流程
│   ├── Settings/                  # 配置 + Keychain (token) + SettingsWindow 6 tab UI
│   └── ClaudeIntegration/
│       ├── HookInstaller.swift    # 写 settings.json + hooks/vibelight.sh
│       └── HookScript.swift       # 内嵌脚本字符串
└── Resources/
    └── vibelight.sh
```

## 13. 技术栈

- Swift 5.9 / SwiftUI
- macOS 13+
- Network.framework：HTTP server（NWListener） + 网络监测（NWPathMonitor）
- Keychain：HA token
- UserDefaults：非敏感配置
- 日志：os.Logger + 文件
- 无第三方依赖

## 14. 开发节奏（粗）

| 阶段 | 内容 | 估时 |
|---|---|---|
| Spike | Python 实现 broker，跑通 hook → HA 全链路（Broker-emulated 模式），验证状态机和颜色效果 | 1 d |
| MVP Swift app | menubar 图标 + 内嵌 broker + BrokerEmulatedDriver + 写死配置，复刻 Spike 行为 | 3 d |
| Onboarding | HA 连接 / 灯选择 / 网络确认 / hook 自动写入 / 灯效测试 | 1.5 d |
| Settings 窗口 | 6 个 tab 完整 UI + 颜色编辑器 + Keychain 管理 | 1.5 d |
| Scene pack | ScenePackDriver + ScenePackInstaller + 模式切换 UI | 1 d |
| 网络检测 + Pause + 可观察性 | NWPathMonitor + HA ping + 菜单 Pause / Sessions / Logs | 1 d |
| 打磨 | 图标动画、错误提示、日志格式 | 1 d |

总计约 10 个工作日。

## 15. v2 / 未来扩展

- **Codex 支持**：通过 wrap CLI 或解析 stdout 实现
- **更多灯具生态**：Hue / Yeelight / WLED driver
- **iOS / iPadOS 端**：菜单栏图标的远程版本（让你在另一个屏幕也能看见状态）
- **声音 / 振动反馈**：ERROR 时桌面通知 + 可选声音
- **多用户**：一个 HA 同时接入多个 Claude 用户的灯带（家庭场景）

## 16. 决策记录

| 决策 | 选项 | 选择 | 理由 |
|---|---|---|---|
| 灯具生态 | Hue / Yeelight / HA / WLED | **Home Assistant** | 用户已有 HA，最灵活 |
| v1 Agent 支持 | Claude / Codex / 两者 | **仅 Claude Code** | Claude 有官方 hooks，Codex 推迟 |
| 多 session 仲裁 | 焦点 / 优先级 / 单 session | **优先级仲裁** | 用户会并行多 session |
| 思考 vs 处理 | 区分 / 合并 / 严格采集 | **合并** | hooks 颗粒度不支持区分，强行做会脆弱 |
| 部署形态 | launchd 守护 / menubar app | **menubar app** | 可见性、onboarding、Pause 都更顺 |
| HA 通信 | REST / WebSocket | **REST** | 事件驱动，无需长连接 |
| 灯效实现 | broker 端 timer / HA scene / 两者都做 | **两者都做，默认 Broker-emulated** | 默认零 HA 配置开箱即爽；Scene pack 作为可选升级保留高级体验 |
| 在家检测 | SSID / HA 可达性 / 混合 | **混合（C）** | 无需位置权限 + 用户能"看见家" |
