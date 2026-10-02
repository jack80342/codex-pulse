#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
./scripts/build-app.sh

codex_pulse_source="$PWD/.build/app/Codex Pulse.app"
codex_pulse_destination="/Applications/Codex Pulse.app"
if [ -L "$codex_pulse_destination" ]; then
    printf '%s\n' '安装路径是符号链接，未覆盖。' >&2
    exit 1
fi
if [ -e "$codex_pulse_destination" ]; then
    codex_pulse_identifier=$(plutil -extract CFBundleIdentifier raw -o - "$codex_pulse_destination/Contents/Info.plist")
    if [ "$codex_pulse_identifier" != 'dev.codexpulse.mac' ]; then
        printf '%s\n' '安装位置已被其他应用占用，未覆盖。' >&2
        exit 1
    fi
fi
if pgrep -f '^/Applications/Codex Pulse[.]app/Contents/MacOS/CodexPulseApp([[:space:]]|$)' >/dev/null; then
    printf '%s\n' '请先退出已安装的 Codex Pulse，再更新应用。' >&2
    exit 1
fi

codex_pulse_staging=$(mktemp -d /Applications/.CodexPulse-install.XXXXXX)
cleanup() {
    if [ -d "$codex_pulse_staging/previous.app" ] && [ ! -e "$codex_pulse_destination" ]; then
        mv "$codex_pulse_staging/previous.app" "$codex_pulse_destination"
    fi
    rm -rf "$codex_pulse_staging"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
ditto "$codex_pulse_source" "$codex_pulse_staging/Codex Pulse.app"
codesign --verify --deep --strict "$codex_pulse_staging/Codex Pulse.app"
if [ -e "$codex_pulse_destination" ]; then
    mv "$codex_pulse_destination" "$codex_pulse_staging/previous.app"
fi
mv "$codex_pulse_staging/Codex Pulse.app" "$codex_pulse_destination"
printf '%s\n' "应用已安装：$codex_pulse_destination"
