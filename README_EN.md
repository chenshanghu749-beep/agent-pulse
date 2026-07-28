# Agent Pulse

<p align="center">
  <img src="docs/assets/agent-pulse.png" alt="Agent Pulse icon" width="160">
</p>

<p align="center">
  <a href="README.md">中文</a> | English
</p>

<p align="center">
  <img alt="Release" src="https://img.shields.io/badge/release-2.8.0-111111">
  <img alt="Stars" src="https://img.shields.io/github/stars/chenshanghu749-beep/agent-pulse">
  <img alt="Swift" src="https://img.shields.io/badge/swift-5-F05138">
  <img alt="AppKit" src="https://img.shields.io/badge/AppKit-native-111111">
  <img alt="macOS" src="https://img.shields.io/badge/macOS-13%2B-111111">
</p>

Agent Pulse is a native macOS menu bar routing and status tool for Codex, Cursor, and Trae. It provides Agent selection, Codex provider routing, usage monitoring, and task status without modifying those apps.

<p align="center">
  <img src="docs/assets/menu-bar-preview.png" alt="Agent Pulse menu bar preview" width="100%">
</p>

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/chenshanghu749-beep/agent-pulse/main/install.sh | zsh
```

Agent Pulse launches automatically after installation. The default location is `~/Applications/Agent Pulse.app`.

## Core Features

| Feature | Description |
| --- | --- |
| Agent selection | Select, monitor, and launch Codex, Cursor, or Trae |
| Route switching | Quickly switch between the official OpenAI route and multiple custom providers |
| Usage display | Show official OpenAI/Cursor usage and CodeAPI provider balances for Cursor or Trae |
| Task status | Read Codex logs, Cursor Hooks, and Trae Hooks: red for execution, yellow for tools, and green for completion |
| Session continuity | Never rewrite the Codex, Cursor, or Trae session database |

Agent Pulse supports the Responses API and can locally convert Chat Completions providers such as DeepSeek to the protocol required by Codex. Cursor BYOK remains managed by Cursor’s official Models settings.

## Usage

1. Open Agent Pulse and select `Codex`, `Cursor`, or `Trae`.
2. Codex supports official OpenAI and tested third-party providers.
3. Cursor and Trae keep managing models and API keys in their own settings; Agent Pulse can display a selected provider balance.
4. Click `Apply and Open`. Cursor is never force-restarted, while Trae reloads its Hooks without a restart.

The menu bar icon continuously reflects the current task status. A three-color transition animation runs at launch, during route changes, and immediately before a task returns to the completed state.

## Requirements

- Apple Silicon Mac
- macOS 13 or later
- Codex, Cursor, or Trae for macOS installed

## Manual Installation

Download [`Agent-Pulse-2.8.0.dmg`](dist/Agent-Pulse-2.8.0.dmg), open it, and drag `Agent Pulse.app` into `Applications`.

If macOS blocks the first launch, right-click the app in Finder and select `Open`.

## Build from Source

```bash
git clone https://github.com/chenshanghu749-beep/agent-pulse.git
cd agent-pulse
chmod +x build.sh package.sh
./build.sh
./package.sh
```

The app is generated at `build/Agent Pulse.app`, and the installer is generated at `dist/Agent-Pulse-2.8.0.dmg`.

## Privacy and Security

- API keys are stored locally and are never written to the provider list or uploaded to the repository.
- Credential files use `600` permissions and the credential directory uses `700` permissions.
- Relevant local configuration and session metadata are backed up before route changes.
- Official authentication is backed up before entering a third-party route, then restored when switching back while third-party API keys remain isolated.
- Cursor official usage requires explicit consent; the login token is used in memory only and is never copied or persisted.
- Cursor Hooks record only running, tool, and completion states—not prompts, responses, or conversation content.
- Trae Hooks also write only the traffic-light state and event time—not prompts, responses, or conversation content.
- Agent Pulse does not use macOS Keychain and does not repeatedly trigger Keychain authorization prompts.

## Uninstall

Quit Agent Pulse and move `Agent Pulse.app` to Trash. To remove all configuration, delete `~/.codex/agent-pulse/`, the legacy compatibility directory `~/.codex/codeapi-status/`, and `~/Library/Application Support/Agent Pulse/`.

## Support the Project

If Agent Pulse is useful to you, you can support its ongoing maintenance through WeChat.

<p align="center">
  <img src="docs/assets/wechat-pay.jpg" alt="WeChat payment QR code" width="320">
</p>

Current version: `2.8.0`
