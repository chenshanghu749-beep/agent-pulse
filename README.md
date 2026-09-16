# Agent Pulse

<p align="center">
  <img src="docs/assets/agent-pulse.png" alt="Agent Pulse 图标" width="160">
</p>

<p align="center">
  中文 | <a href="README_EN.md">English</a>
</p>

<p align="center">
  <img alt="Release" src="https://img.shields.io/badge/release-3.3.3-111111">
  <img alt="Stars" src="https://img.shields.io/github/stars/chenshanghu749-beep/agent-pulse">
  <img alt="Swift" src="https://img.shields.io/badge/swift-5-F05138">
  <img alt="AppKit" src="https://img.shields.io/badge/AppKit-native-111111">
  <img alt="macOS" src="https://img.shields.io/badge/macOS-13%2B-111111">
</p>

Agent Pulse 是面向 Codex、Cursor、Hermes、Claude CLI 与 OpenCode 的原生 macOS 菜单栏路由与状态工具。它提供 Agent 切换、模型与提供商管理、用量展示和任务状态，无需修改这些 Agent 应用本体。


## 快速安装

```bash
curl -fsSL https://raw.githubusercontent.com/chenshanghu749-beep/agent-pulse/main/install.sh | zsh
```

安装完成后会自动启动 `Agent Pulse`。默认安装位置为 `~/Applications/Agent Pulse.app`。

<p align="center">
  <img src="docs/assets/menu-bar-preview.png" alt="Agent Pulse 菜单栏预览" width="100%">
</p>

## 3.3.3 更新

- 修复 macOS 锁屏唤醒、菜单栏重新布局或余额轮播切换后，状态图标与提供商名称、余额偶发重叠的问题。
- 图标与文字现在作为统一内容渲染，并在显示模式变化时主动重建布局，保持间距稳定。

## 3.3.2 更新

- 修复“监控与历史”卡片悬浮时整体缩放，导致图标和文字插值模糊的问题；现在保留阴影反馈但不再放大内容。
- 历史柱状图新增即时悬浮详情，显示日期、真实指标值与当天采样次数，空数据日期会显示“暂无采样”。
- 悬浮柱增加清晰描边，并继续支持剩余百分比、余额、Token 与费用等不同历史指标。

## 3.3.1 更新

- OpenAI 官方用量兼容 `5h` 与 `7d` 双窗口，状态栏、仪表盘、设置页、下拉菜单和桌面组件统一展示剩余用量。
- 状态栏官方用量使用 `官方 5h 99% · 7d 59%` 紧凑格式，并扩大完整文字区域，避免第二个窗口被裁切。
- 修复 Cursor 1.x 部分账户把小数百分比错误按比例换算，导致剩余用量从 99% 误显示为 59% 的问题。
- 官方用量监控与阈值提醒改为跟随当前限制更紧的窗口，并让余额轮播无需打开仪表盘即可及时刷新。

## 核心功能

| 功能 | 说明 |
| --- | --- |
| Agent 切换 | 在 Codex、Cursor、Hermes、Claude CLI 与 OpenCode 之间选择、监控并快速启动 |
| 路由切换 | 为支持的 Agent 管理官方配置、预设厂商和自定义提供商 |
| 提供商预设 | 内置 DeepSeek、智谱 AI、月之暗面、MiniMax、阶跃星辰、MiMo 与阿里百炼云，也支持自定义 |
| 用量与仪表盘 | 使用双列卡片集中查看官方用量及全部提供商余额，并同步到状态栏和桌面组件 |
| 任务状态 | 支持 Codex 日志、Cursor Hooks 与 Hermes Gateway；红色执行、黄色工具、绿色完成 |
| 监控与历史 | 按模型设置提醒阈值、检测路由状态、查看本地趋势并导出 CSV |
| 配置与安全 | 本地配置快照、差异预览、恢复与脱敏导入导出 |
| 状态外观 | 多种菜单栏状态图标，使用紧凑的黑白卡片快速预览和切换 |
| 会话保持 | 路由切换不改写 Codex、Cursor 或 Hermes 的会话数据库 |
| model_provider | 首次启动读取 Codex 当前配置，可在模型与路由页面中修改并恢复为 openai |

第三方路由统一通过厂商原生 Responses API 直连，不启动本地协议桥接服务。阿里百炼云预设可直接使用 Responses API；智谱 AI 的连接测试会按官方 Chat Completions 接口验证 API Key 与模型，但在智谱开放 Responses API 前不能作为 Codex 直连路由。所有提供商均可在启用前测试 Base URL、API Key 与模型。

## 使用方式

1. 打开 Agent Pulse，选择 `Codex`、`Cursor`、`Hermes`、`Claude CLI` 或 `OpenCode`。
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

下载 [`Agent-Pulse-3.3.3.dmg`](dist/Agent-Pulse-3.3.3.dmg)，打开后将 `Agent Pulse.app` 拖入 `Applications`。

若 macOS 首次运行时阻止打开，请在 Finder 中右键应用并选择“打开”。

## 从源码构建

```bash
git clone https://github.com/chenshanghu749-beep/agent-pulse.git
cd agent-pulse
chmod +x build.sh package.sh
./build.sh
./package.sh
```

构建产物位于 `build/Agent Pulse.app`，安装包位于 `dist/Agent-Pulse-3.3.3.dmg`。

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

当前版本：`3.3.3`
