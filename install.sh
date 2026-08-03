#!/bin/zsh
set -euo pipefail

readonly APP_NAME="Agent Pulse.app"
readonly LEGACY_APP_NAME="Codex Pulse.app"
readonly VERSION="2.9.0"
readonly DMG_NAME="Agent-Pulse-${VERSION}.dmg"
readonly DMG_URL="https://raw.githubusercontent.com/chenshanghu749-beep/agent-pulse/main/dist/${DMG_NAME}"
readonly EXPECTED_SHA256="7ff862f41ce227696038de26c78aae28241c9534b5479aac3d2896c5e7ab959d"

install_dir="${AGENT_PULSE_INSTALL_DIR:-${CODEX_PULSE_INSTALL_DIR:-${CODEAPI_STATUS_INSTALL_DIR:-$HOME/Applications}}}"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/agent-pulse-install.XXXXXX")"
dmg_path="$work_dir/$DMG_NAME"
mount_dir="$work_dir/mount"
mounted=false

cleanup() {
    if [[ "$mounted" == true ]]; then
        /usr/bin/hdiutil detach "$mount_dir" >/dev/null 2>&1 || true
    fi
    /bin/rm -rf "$work_dir"
}
trap cleanup EXIT

/bin/mkdir -p "$mount_dir"
echo "正在下载 Agent Pulse ${VERSION}…"
/usr/bin/curl -fsSL --retry 3 "$DMG_URL" -o "$dmg_path"

actual_sha256="$(/usr/bin/shasum -a 256 "$dmg_path" | /usr/bin/awk '{print $1}')"
if [[ "$actual_sha256" != "$EXPECTED_SHA256" ]]; then
    echo "安装包校验失败，已停止安装。" >&2
    exit 1
fi

/usr/bin/hdiutil attach -nobrowse -readonly -mountpoint "$mount_dir" "$dmg_path" >/dev/null
mounted=true

source_app="$mount_dir/$APP_NAME"
target_app="$install_dir/$APP_NAME"
if [[ ! -d "$source_app" ]]; then
    echo "安装包中未找到 $APP_NAME。" >&2
    exit 1
fi

/bin/mkdir -p "$install_dir"
trash_dir="$HOME/.Trash"
/bin/mkdir -p "$trash_dir"

move_existing_to_trash() {
    local app_path="$1"
    local backup_name="$2"
    [[ -d "$app_path" ]] || return 0
    local backup_path="$trash_dir/$backup_name"
    if [[ -e "$backup_path" ]]; then
        backup_path="$trash_dir/${backup_name%.app} $(/bin/date +%Y%m%d-%H%M%S).app"
    fi
    /bin/mv "$app_path" "$backup_path"
    echo "旧版已移到废纸篓：$backup_path"
}

move_existing_to_trash "$target_app" "Agent Pulse（升级前）.app"
legacy_app="$install_dir/$LEGACY_APP_NAME"
if [[ -d "$legacy_app" && "$legacy_app" != "$target_app" ]]; then
    move_existing_to_trash "$legacy_app" "Codex Pulse（升级前）.app"
fi
/usr/bin/ditto "$source_app" "$target_app"
lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
widget_extension="$target_app/Contents/PlugIns/AgentPulseWidget.appex"
if [[ -x "$lsregister" ]]; then
    "$lsregister" -f "$target_app" >/dev/null 2>&1 || true
fi
if [[ -d "$widget_extension" ]]; then
    /usr/bin/pluginkit -a "$widget_extension" >/dev/null 2>&1 || true
fi
/usr/bin/hdiutil detach "$mount_dir" >/dev/null
mounted=false

echo "已安装到：$target_app"
echo "正在启动 Agent Pulse…"
/usr/bin/open "$target_app"
