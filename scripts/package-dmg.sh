#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
if [ -z "${CODEX_PULSE_APP_PATH:-}" ]; then
    ./scripts/build-app.sh
fi

codex_pulse_source=${CODEX_PULSE_APP_PATH:-"$PWD/.build/app/Codex Pulse.app"}
codex_pulse_version=$(plutil -extract CFBundleShortVersionString raw -o - "$codex_pulse_source/Contents/Info.plist")
codex_pulse_output_directory=${CODEX_PULSE_DIST_DIRECTORY:-"$PWD/.build/dist"}
mkdir -p "$codex_pulse_output_directory"
codex_pulse_staging=$(mktemp -d "$PWD/.build/dmg.XXXXXX")
codex_pulse_temporary=$(mktemp "$codex_pulse_output_directory/.CodexPulse-dmg.XXXXXX")
trap 'rm -rf "$codex_pulse_staging"; rm -f "$codex_pulse_temporary" "$codex_pulse_temporary.dmg"' EXIT
ditto "$codex_pulse_source" "$codex_pulse_staging/Codex Pulse.app"
ln -s /Applications "$codex_pulse_staging/Applications"
codesign --verify --deep --strict "$codex_pulse_staging/Codex Pulse.app"
hdiutil create -volname 'Codex Pulse' -srcfolder "$codex_pulse_staging" -format UDZO "$codex_pulse_temporary.dmg"
codex_pulse_output="$codex_pulse_output_directory/Codex-Pulse-$codex_pulse_version.dmg"
mv -f "$codex_pulse_temporary.dmg" "$codex_pulse_output"
printf '%s\n' "安装包已生成：$codex_pulse_output"
