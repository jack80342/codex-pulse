#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

# Swift 6.4 的 swiftbuild 后端在部分 CLT 环境遗漏 Testing 宏插件，显式提供当前工具链的插件。
codex_pulse_swiftc=$(xcrun --find swiftc)
codex_pulse_plugin="$(dirname "$(dirname "$codex_pulse_swiftc")")/lib/swift/host/plugins/testing/libTestingMacros.dylib"
if [ -f "$codex_pulse_plugin" ]; then
    exec swift test --disable-xctest -Xswiftc -load-plugin-library -Xswiftc "$codex_pulse_plugin" "$@"
fi
exec swift test --disable-xctest "$@"
