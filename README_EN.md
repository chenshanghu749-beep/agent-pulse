# Agent Pulse

<p align="center">
  <img src="docs/assets/agent-pulse.png" alt="Agent Pulse icon" width="160">
</p>

<p align="center">
  <a href="README.md">中文</a> | English
</p>

<p align="center">
  <img alt="Release" src="https://img.shields.io/badge/release-3.1.2-111111">
  <img alt="Stars" src="https://img.shields.io/github/stars/chenshanghu749-beep/agent-pulse">
  <img alt="Swift" src="https://img.shields.io/badge/swift-5-F05138">
  <img alt="AppKit" src="https://img.shields.io/badge/AppKit-native-111111">
  <img alt="macOS" src="https://img.shields.io/badge/macOS-13%2B-111111">
</p>

Agent Pulse is a native macOS menu bar routing and status tool for Codex, Cursor, and Hermes. It provides Agent selection, provider and model management, usage monitoring, and task status without modifying those apps.

<p align="center">
  <img src="docs/assets/menu-bar-preview.png" alt="Agent Pulse menu bar preview" width="100%">
</p>

## What's New in 3.1.2

- Added Monitoring and History with per-Agent/model usage or balance alerts, reset timing, route health checks, local trends, and CSV export.
- Added Configuration and Security with local snapshots, automatic pre-restore backups, redacted diffs, and safe provider import/export.
- Model selection now uses full-width clickable banners; connection results and latency stay inside each model row, with a monochrome animated selection border.
- Refined the status appearance gallery, Agent selector, buttons, popup controls, and spacing between menu bar style icons and labels.
- Configuration backups and usage history stay local, exclude Keychain API keys, and never modify Agent session databases.

## What's New in 3.0.2

- Fixed stale balances in the model configuration list; official usage and provider balances now stay synchronized with the menu bar.
- Disabled automatic legacy-session migration at startup, preserved the existing `model_provider` during route changes, and kept the Codex session database read-only.
- Added a Codex-only `model_provider` editor with automatic `config.toml` backups.
- `Update Now` can quit the app, download and verify the installer in the background, install it, and reopen Agent Pulse automatically.

## What's New in 3.0.1

- Added a monochrome dual-gear status icon with counter-rotating gears.
- Running, waiting, and ready states use high, medium, and low rotation speeds.
- Uses a native composite menu bar image so animation remains synchronized across multiple displays.

## What's New in 3.0.0

- Added Hermes Agent detection, launching, provider management, and model switching.
- Added Hermes task state, daily tokens, API calls, and local cost reporting.
- When a Hermes provider supports balance lookup, the dashboard and menu bar prioritize its balance and fall back to tokens when unavailable.
- Hermes configuration is backed up before model changes, and active Hermes tasks are never restarted.

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/chenshanghu749-beep/agent-pulse/main/install.sh | zsh
```

Agent Pulse launches automatically after installation. The default location is `~/Applications/Agent Pulse.app`.

## Core Features

| Feature | Description |
| --- | --- |
| Agent selection | Select, monitor, and launch Codex, Cursor, or Hermes |
| Route switching | Manage official configurations, presets, and custom providers for Codex and Hermes |
| Provider presets | Includes DeepSeek, Zhipu AI, Moonshot, MiniMax, StepFun, MiMo, and Alibaba Model Studio, plus custom providers |
| Usage dashboard | Review official usage, supported provider balances, and Hermes local tokens, requests, and costs |
| Task status | Read Codex logs, Cursor Hooks, and Hermes Gateway state: red for execution, yellow for tools, and green for completion |
| Monitoring and history | Set per-model alerts, check route health, review local trends, and export CSV |
| Configuration security | Create local snapshots, preview diffs, restore, and import/export redacted settings |
| Status appearance | Preview and switch among multiple menu bar indicators in a compact monochrome gallery |
| Session continuity | Route switching never rewrites the Codex, Cursor, or Hermes session database |
| model_provider | Read the current Codex value on first launch; edit or restore it from the model and route page |

Third-party routes connect directly through each provider's native Responses API, without a local protocol bridge. The Alibaba Model Studio preset supports Responses API directly. Zhipu AI connection tests use its official Chat Completions endpoint to validate the key and model, but Zhipu cannot be used as a direct Codex route until it exposes a Responses-compatible endpoint. Cursor BYOK remains managed by Cursor’s official Models settings.

## Usage

1. Open Agent Pulse and select `Codex`, `Cursor`, or `Hermes`.
2. Codex supports the official OpenAI route plus preset or custom providers with connection testing.
3. Cursor keeps managing models and API keys in its own settings; Agent Pulse can display a selected provider balance.
4. Hermes can keep its current configuration or use an Agent Pulse provider and model without restarting an active task.
5. Click `Apply and Open` to synchronize the selected Agent, balance or token usage, and task state in the menu bar.

The menu bar icon continuously reflects the current task status. A three-color transition animation runs at launch, during route changes, and immediately before a task returns to the completed state.

## Requirements

- Apple Silicon Mac
- macOS 13 or later
- Codex, Cursor, or Hermes for macOS installed

## Manual Installation

Download [`Agent-Pulse-3.1.2.dmg`](dist/Agent-Pulse-3.1.2.dmg), open it, and drag `Agent Pulse.app` into `Applications`.

If macOS blocks the first launch, right-click the app in Finder and select `Open`.

## Build from Source

```bash
git clone https://github.com/chenshanghu749-beep/agent-pulse.git
cd agent-pulse
chmod +x build.sh package.sh
./build.sh
./package.sh
```

The app is generated at `build/Agent Pulse.app`, and the installer is generated at `dist/Agent-Pulse-3.1.2.dmg`.

## Privacy and Security

- API keys are stored locally and are never written to the provider list or uploaded to the repository.
- Credential files use `600` permissions and the credential directory uses `700` permissions.
- Relevant local configuration and session metadata are backed up before route changes.
- Official authentication is backed up before entering a third-party route, then restored when switching back while third-party API keys remain isolated.
- Cursor official usage requires explicit consent; the login token is used in memory only and is never copied or persisted.
- Cursor Hooks record only running, tool, and completion states—not prompts, responses, or conversation content.
- Before changing Hermes models, Agent Pulse creates a local restore snapshot in `~/.hermes/` with `600` permissions and restores it when “current configuration” is selected.
- Normal startup and route switching never migrate, copy, or rewrite legacy sessions. Editing `model_provider` only updates `config.toml` after saving a local configuration backup.
- Agent Pulse does not use macOS Keychain and does not repeatedly trigger Keychain authorization prompts.

## Uninstall

Quit Agent Pulse and move `Agent Pulse.app` to Trash. To remove all configuration, delete `~/.codex/agent-pulse/`, the legacy compatibility directory `~/.codex/codeapi-status/`, and `~/Library/Application Support/Agent Pulse/`.

## Support the Project

If Agent Pulse is useful to you, you can support its ongoing maintenance through WeChat.

<p align="center">
  <img src="docs/assets/wechat-pay.jpg" alt="WeChat payment QR code" width="320">
</p>

Current version: `3.1.2`
