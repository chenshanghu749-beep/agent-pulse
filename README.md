# Agent Pulse

<p align="center">
  <img src="docs/assets/agent-pulse.png" alt="Agent Pulse 图标" width="160">
</p>

<p align="center">
  中文 | <a href="README_EN.md">English</a>
</p>

<p align="center">
  <img alt="Release" src="https://img.shields.io/badge/release-3.2.0-111111">
  <img alt="Stars" src="https://img.shields.io/github/stars/chenshanghu749-beep/agent-pulse">
  <img alt="Swift" src="https://img.shields.io/badge/swift-5-F05138">
  <img alt="AppKit" src="https://img.shields.io/badge/AppKit-native-111111">
  <img alt="macOS" src="https://img.shields.io/badge/macOS-13%2B-111111">
</p>

Agent Pulse 是面向 Codex、Cursor 与 Hermes 的原生 macOS 菜单栏路由与状态工具。它提供 Agent 切换、模型与提供商管理、用量展示和任务状态，无需修改这些 Agent 应用本体。


## 快速安装

```bash
curl -fsSL https://raw.githubusercontent.com/chenshanghu749-beep/agent-pulse/main/install.sh | zsh
```

安装完成后会自动启动 `Agent Pulse`。默认安装位置为 `~/Applications/Agent Pulse.app`。

<p align="center">
  <img src="docs/assets/menu-bar-preview.png" alt="Agent Pulse 菜单栏预览" width="100%">
</p>

## 3.2.0 更新

- 新增诊断中心：集中展示 Agent、版本路径、路由模型、余额刷新、任务事件、状态监听与配置冲突，并支持复制脱敏报告。
- Codex 路由切换升级为安全事务：切换前预检与自动备份，写入和启动后再次验证，失败时自动恢复认证与 `config.toml`，始终不修改会话数据库。
- 扩展新版 Codex 任务事件兼容，支持识别状态长期停留，并可一键重新初始化任务监听。
- 监控历史支持 7/30/90 天趋势、Token 与费用汇总、保留周期、清空记录、通知冷却，以及跨重启保存路由健康状态。
- 配置快照支持名称、备注和选择恢复范围；导入前显示新增、修改、删除预览，并检查重复配置与无效 URL。
- 模型连接检测支持倒计时、取消、时间戳和鉴权失败、模型不存在、连接超时分类；模型卡片支持键盘选择。
- 修复深色应用主题下风车/齿轮菜单栏文字颜色错误，以及诊断中心内容被滚动容器裁剪的问题。

## 3.1.2 更新

- 新增“监控与历史”：按 Agent 与模型设置用量或余额提醒、查看重置时间、检测路由健康，并导出本地用量历史。
- 新增“配置与安全”：创建本地快照、恢复前自动备份、预览脱敏差异，以及安全导入导出提供商配置。
- 模型列表改为整行 Banner 选择，连接状态与延迟直接显示在对应模型中，选中项使用黑白流动边框。
- 优化状态与外观页面、Agent 选择区域、按钮和选择控件；菜单栏样式图标与文字间距更清晰。
- 配置备份与历史数据只保存在本机，不保存或导出钥匙串 API Key，也不修改 Agent 会话数据库。

## 3.0.2 更新

- 修复状态栏余额变化后，模型配置列表仍停留旧值的问题；官方用量与提供商余额现在会同步刷新。
- 停止启动时自动迁移旧会话，路由切换保留现有 `model_provider`，不改写 Codex 会话数据库。
- 新增 Codex 专属 `model_provider` 配置入口，修改前自动备份 `config.toml`。
- “立即更新”支持退出应用后在后台下载、校验、安装并自动重新打开。

## 核心功能

| 功能 | 说明 |
| --- | --- |
| Agent 切换 | 在 Codex、Cursor 与 Hermes 之间选择、监控并快速启动 |
| 路由切换 | 为 Codex 与 Hermes 管理官方配置、预设厂商和自定义提供商 |
| 提供商预设 | 内置 DeepSeek、智谱 AI、月之暗面、MiniMax、阶跃星辰、MiMo 与阿里百炼云，也支持自定义 |
| 用量与仪表盘 | 集中查看官方用量、提供商余额，以及 Hermes 本地 Token、请求与费用 |
| 任务状态 | 支持 Codex 日志、Cursor Hooks 与 Hermes Gateway；红色执行、黄色工具、绿色完成 |
| 监控与历史 | 按模型设置提醒阈值、检测路由状态、查看本地趋势并导出 CSV |
| 配置与安全 | 本地配置快照、差异预览、恢复与脱敏导入导出 |
| 状态外观 | 多种菜单栏状态图标，使用紧凑的黑白卡片快速预览和切换 |
| 会话保持 | 路由切换不改写 Codex、Cursor 或 Hermes 的会话数据库 |
| model_provider | 首次启动读取 Codex 当前配置，可在模型与路由页面中修改并恢复为 openai |

第三方路由统一通过厂商原生 Responses API 直连，不启动本地协议桥接服务。阿里百炼云预设可直接使用 Responses API；智谱 AI 的连接测试会按官方 Chat Completions 接口验证 API Key 与模型，但在智谱开放 Responses API 前不能作为 Codex 直连路由。所有提供商均可在启用前测试 Base URL、API Key 与模型。

## 使用方式

1. 打开 Agent Pulse，选择 `Codex`、`Cursor` 或 `Hermes`。
2. Codex 可选择 OpenAI 官方路由，或添加预设/自定义提供商并测试连接。
3. Cursor 继续在官方应用中管理模型和 API Key；Agent Pulse 可绑定一个已配置的提供商展示余额。
4. Hermes 可保留当前配置，也可以添加提供商并选择模型；切换后不会重启正在运行的任务。
5. 点击“应用并打开”，状态栏会同步当前 Agent、余额或 Token 以及任务状态。

菜单栏图标会持续显示当前任务状态。启动、切换路由以及任务完成前会播放一次三色过渡动画。

## 系统要求

- Apple Silicon Mac
- macOS 13 或更高版本
- 已安装 Codex、Cursor 或 Hermes macOS 应用

## 手动安装

下载 [`Agent-Pulse-3.2.0.dmg`](dist/Agent-Pulse-3.2.0.dmg)，打开后将 `Agent Pulse.app` 拖入 `Applications`。

若 macOS 首次运行时阻止打开，请在 Finder 中右键应用并选择“打开”。

## 从源码构建

```bash
git clone https://github.com/chenshanghu749-beep/agent-pulse.git
cd agent-pulse
chmod +x build.sh package.sh
./build.sh
./package.sh
```

构建产物位于 `build/Agent Pulse.app`，安装包位于 `dist/Agent-Pulse-3.2.0.dmg`。

## 隐私与安全

- API Key 仅保存在本机，不会写入提供商列表或上传到仓库。
- 凭据文件权限为 `600`，凭据目录权限为 `700`。
- 路由切换前会备份相关本地配置，不会修改 Codex 会话数据库。
- Cursor 官方用量需用户明确授权；登录令牌仅在请求期间保留于内存，不会复制或持久化。
- Cursor Hooks 只记录执行、工具和完成状态，不记录提示词、回复或会话内容。
- Hermes 模型切换前会在 `~/.hermes/` 保存权限为 `600` 的本地恢复快照；切回“当前配置”时自动恢复。
- 普通启动和路由切换不会迁移、复制或改写旧会话；`model_provider` 修改只写入 `config.toml`，并先保存配置备份。
- 进入第三方路由前会备份官方登录，切回官方时自动恢复并隔离第三方 API Key。
- 应用不使用 macOS 钥匙串，不会反复触发钥匙串授权弹窗。

## 卸载

退出 Agent Pulse，将 `Agent Pulse.app` 移到废纸篓即可。需要彻底清理配置时，可删除 `~/.codex/agent-pulse/`、旧版兼容目录 `~/.codex/codeapi-status/` 与 `~/Library/Application Support/Agent Pulse/`。

## 支持项目

如果 Agent Pulse 对你有帮助，可以通过微信支持项目的持续维护。

<details>
  <summary>📷 点击展开收款码</summary>

  <p align="center">
    <img src="docs/assets/wechat-pay.jpg" alt="微信收款码" width="320">
  </p>

</details>

当前版本：`3.2.0`
