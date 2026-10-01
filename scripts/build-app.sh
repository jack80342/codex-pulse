#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift build --product CodexPulseApp
codex_pulse_bin=$(swift build --show-bin-path)
codex_pulse_bundle="$PWD/.build/app/Codex Pulse.app"
mkdir -p "$codex_pulse_bundle/Contents/MacOS"
codex_pulse_tmp=$(mktemp "$codex_pulse_bundle/Contents/MacOS/.CodexPulseApp.XXXXXX")
trap 'rm -f "$codex_pulse_tmp"' EXIT
cp -p "$codex_pulse_bin/CodexPulseApp" "$codex_pulse_tmp"
mv -f "$codex_pulse_tmp" "$codex_pulse_bundle/Contents/MacOS/CodexPulseApp"
cp Resources/Info.plist "$codex_pulse_bundle/Contents/Info.plist"
codesign --force --sign - "$codex_pulse_bundle"
printf '%s\n' "应用已生成：$codex_pulse_bundle"
