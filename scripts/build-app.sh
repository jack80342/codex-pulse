#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
codex_pulse_configuration=${CODEX_PULSE_BUILD_CONFIGURATION:-debug}
case "$codex_pulse_configuration" in
    debug|release) ;;
    *) printf '%s\n' '构建配置必须是 debug 或 release。' >&2; exit 1 ;;
esac
swift build --configuration "$codex_pulse_configuration" --product CodexPulseApp
codex_pulse_bin=$(swift build --configuration "$codex_pulse_configuration" --show-bin-path)
codex_pulse_bundle=${CODEX_PULSE_APP_PATH:-"$PWD/.build/app/Codex Pulse.app"}
mkdir -p "$codex_pulse_bundle/Contents/MacOS"
codex_pulse_tmp=$(mktemp "$codex_pulse_bundle/Contents/MacOS/.CodexPulseApp.XXXXXX")
trap 'rm -f "$codex_pulse_tmp"' EXIT
cp -p "$codex_pulse_bin/CodexPulseApp" "$codex_pulse_tmp"
mv -f "$codex_pulse_tmp" "$codex_pulse_bundle/Contents/MacOS/CodexPulseApp"
cp Resources/Info.plist "$codex_pulse_bundle/Contents/Info.plist"
codex_pulse_resources="$codex_pulse_bin/CodexPulse_CodexPulseCore.bundle"
if [ ! -d "$codex_pulse_resources" ]; then
    printf '%s\n' '未生成语言资源包，停止打包。' >&2
    exit 1
fi
mkdir -p "$codex_pulse_bundle/Contents/Resources"
cp Resources/AppIcon.icns "$codex_pulse_bundle/Contents/Resources/AppIcon.icns"
ditto "$codex_pulse_resources" "$codex_pulse_bundle/Contents/Resources/CodexPulse_CodexPulseCore.bundle"
cp LICENSE "$codex_pulse_bundle/Contents/Resources/LICENSE"
codesign --force --sign - "$codex_pulse_bundle"
printf '%s\n' "应用已生成：$codex_pulse_bundle"
