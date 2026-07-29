# Agent Pulse

<p align="center">
  <img src="docs/assets/agent-pulse.png" alt="Agent Pulse 图标" width="160">
</p>

<p align="center">
  中文 | <a href="README_EN.md">English</a>
</p>

<p align="center">
  <img alt="Release" src="https://img.shields.io/badge/release-2.8.1-111111">
  <img alt="Stars" src="https://img.shields.io/github/stars/chenshanghu749-beep/agent-pulse">
  <img alt="Swift" src="https://img.shields.io/badge/swift-5-F05138">
  <img alt="AppKit" src="https://img.shields.io/badge/AppKit-native-111111">
  <img alt="macOS" src="https://img.shields.io/badge/macOS-13%2B-111111">
</p>

Agent Pulse 是面向 Codex、Cursor 与 Trae 的原生 macOS 菜单栏路由与状态工具。它提供 Agent 切换、Codex 官方与第三方模型路由、用量展示和任务状态，无需修改这些 Agent 应用本体。


## 快速安装

```bash
curl -fsSL https://raw.githubusercontent.com/chenshanghu749-beep/agent-pulse/main/install.sh | zsh
```

安装完成后会自动启动 `Agent Pulse`。默认安装位置为 `~/Applications/Agent Pulse.app`。

<p align="center">
  <img src="docs/assets/menu-bar-preview.png" alt="Agent Pulse 菜单栏预览" width="100%">
</p>


## 核心功能

| 功能 | 说明 |
| --- | --- |
| Agent 切换 | 在 Codex、Cursor 与 Trae 之间选择、监控并快速启动 |
| 路由切换 | 在 OpenAI 官方路由和多个自定义提供商之间快速切换 |
| 用量展示 | 查看 OpenAI/Cursor 官方用量及 Cursor/Trae 对应的 CodeAPI 提供商余额 |
| 任务状态 | 支持 Codex 日志、Cursor Hooks 与 Trae Hooks；红色执行、黄色工具、绿色完成 |
| 会话保持 | 不改写 Codex、Cursor 或 Trae 的会话数据库 |
| 旧会话兼容 | 首次启动检测旧第三方会话，经用户确认后创建 OpenAI 兼容副本，并保留完整备份 |

支持 Responses API，并可在本机将 DeepSeek 等 Chat Completions 接口转换为 Codex 所需协议。GPT‑5.6 第三方路由会自动应用 Responses Lite 兼容配置。提供商配置支持连接测试，可在启用前校验 Base URL、API Key、模型与协议。

## 使用方式

1. 打开 Agent Pulse，选择 `Codex`、`Cursor` 或 `Trae`。
2. Codex 可选择 OpenAI 官方路由，或配置第三方提供商并测试连接。
3. Cursor 与 Trae 继续在各自应用中管理模型和 API Key；Agent Pulse 可绑定一个已配置的提供商展示余额。
4. 点击“应用并打开”。Cursor 不会被强制重启；Trae Hooks 会实时加载，无需重启。

菜单栏图标会持续显示当前任务状态。启动、切换路由以及任务完成前会播放一次三色过渡动画。

## 系统要求

- Apple Silicon Mac
- macOS 13 或更高版本
- 已安装 Codex、Cursor 或 Trae macOS 应用

## 手动安装

下载 [`Agent-Pulse-2.8.1.dmg`](dist/Agent-Pulse-2.8.1.dmg)，打开后将 `Agent Pulse.app` 拖入 `Applications`。

若 macOS 首次运行时阻止打开，请在 Finder 中右键应用并选择“打开”。

## 从源码构建

```bash
git clone https://github.com/chenshanghu749-beep/agent-pulse.git
cd agent-pulse
chmod +x build.sh package.sh
./build.sh
./package.sh
```

构建产物位于 `build/Agent Pulse.app`，安装包位于 `dist/Agent-Pulse-2.8.1.dmg`。

## 隐私与安全

- API Key 仅保存在本机，不会写入提供商列表或上传到仓库。
- 凭据文件权限为 `600`，凭据目录权限为 `700`。
- 路由切换前会备份相关本地配置，不会修改 Codex 会话数据库。
- Cursor 官方用量需用户明确授权；登录令牌仅在请求期间保留于内存，不会复制或持久化。
- Cursor Hooks 只记录执行、工具和完成状态，不记录提示词、回复或会话内容。
- Trae Hooks 同样只写入红黄绿状态与事件时间，不读取提示词、回复或会话内容。
- 旧会话迁移只在用户确认后执行；源会话保持不变，数据库、配置和源 JSONL 会先保存到本地备份目录。
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

当前版本：`2.8.1`
