#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

codex_pulse_identity=${CODEX_PULSE_SIGN_IDENTITY:-}
codex_pulse_profile=${CODEX_PULSE_NOTARY_PROFILE:-}
case "$codex_pulse_identity" in
    'Developer ID Application:'*) ;;
    *) printf '%s\n' '请通过 CODEX_PULSE_SIGN_IDENTITY 指定完整的 Developer ID Application 证书名称。' >&2; exit 1 ;;
esac
if [ -z "$codex_pulse_profile" ]; then
    printf '%s\n' '请通过 CODEX_PULSE_NOTARY_PROFILE 指定 notarytool 钥匙串配置名称。' >&2
    exit 1
fi
if ! security find-identity -v -p codesigning | awk -v name="\"$codex_pulse_identity\"" '
    index($0, name) { found = 1 }
    END { exit !found }
'; then
    printf '%s\n' '未找到有效且包含私钥的指定 Developer ID Application 证书。' >&2
    exit 1
fi
xcrun --find notarytool >/dev/null
xcrun --find stapler >/dev/null

mkdir -p "$PWD/.build"
codex_pulse_work=$(mktemp -d "$PWD/.build/notarization.XXXXXX")
printf '%s\n' "本次公证文件与日志：$codex_pulse_work"
xcrun notarytool history --keychain-profile "$codex_pulse_profile" --output-format json > "$codex_pulse_work/credential-check.json"

codex_pulse_app="$codex_pulse_work/Codex Pulse.app"
CODEX_PULSE_BUILD_CONFIGURATION=release CODEX_PULSE_APP_PATH="$codex_pulse_app" ./scripts/build-app.sh
codesign --force --options runtime --timestamp --sign "$codex_pulse_identity" "$codex_pulse_app"
codesign --verify --deep --strict "$codex_pulse_app"
codesign --display --verbose=4 "$codex_pulse_app" 2> "$codex_pulse_work/app-signature.txt"

notarize() {
    codex_pulse_archive=$1
    codex_pulse_label=$2
    codex_pulse_result="$codex_pulse_work/$codex_pulse_label-notary-result.json"
    codex_pulse_submission_ok=true
    if ! xcrun notarytool submit "$codex_pulse_archive" --keychain-profile "$codex_pulse_profile" --wait --output-format json > "$codex_pulse_result"; then
        codex_pulse_submission_ok=false
    fi
    codex_pulse_submission_id=$(plutil -extract id raw -o - "$codex_pulse_result" 2>/dev/null || true)
    codex_pulse_submission_status=$(plutil -extract status raw -o - "$codex_pulse_result" 2>/dev/null || true)
    if [ -n "$codex_pulse_submission_id" ]; then
        if ! xcrun notarytool log "$codex_pulse_submission_id" --keychain-profile "$codex_pulse_profile" "$codex_pulse_work/$codex_pulse_label-notary-log.json"; then
            printf '%s\n' "无法下载公证日志，提交 ID：$codex_pulse_submission_id" >&2
            exit 1
        fi
    fi
    if [ "$codex_pulse_submission_ok" != true ] || [ "$codex_pulse_submission_status" != Accepted ]; then
        printf '%s\n' "公证未通过，状态：${codex_pulse_submission_status:-未知}；结果与日志保留于 $codex_pulse_work。" >&2
        exit 1
    fi
}

# 先附加应用凭证，再将该应用放入最终 DMG；最终容器也单独公证并附加凭证。
ditto -c -k --keepParent "$codex_pulse_app" "$codex_pulse_work/Codex-Pulse.zip"
notarize "$codex_pulse_work/Codex-Pulse.zip" app
xcrun stapler staple "$codex_pulse_app"
xcrun stapler validate "$codex_pulse_app"
syspolicy_check distribution "$codex_pulse_app"
spctl --assess --type execute --verbose=4 "$codex_pulse_app"

CODEX_PULSE_APP_PATH="$codex_pulse_app" CODEX_PULSE_DIST_DIRECTORY="$codex_pulse_work" ./scripts/package-dmg.sh
codex_pulse_version=$(plutil -extract CFBundleShortVersionString raw -o - "$codex_pulse_app/Contents/Info.plist")
codex_pulse_dmg="$codex_pulse_work/Codex-Pulse-$codex_pulse_version.dmg"
codesign --force --timestamp --sign "$codex_pulse_identity" "$codex_pulse_dmg"
codesign --verify --strict "$codex_pulse_dmg"
notarize "$codex_pulse_dmg" dmg
xcrun stapler staple "$codex_pulse_dmg"
xcrun stapler validate "$codex_pulse_dmg"
hdiutil verify "$codex_pulse_dmg"
spctl --assess --type open --context context:primary-signature --verbose=4 "$codex_pulse_dmg"

codex_pulse_final_directory="$PWD/.build/dist/notarized"
mkdir -p "$codex_pulse_final_directory"
codex_pulse_final_tmp=$(mktemp "$codex_pulse_final_directory/.CodexPulse.XXXXXX")
trap 'rm -f "$codex_pulse_final_tmp"' EXIT
cp -p "$codex_pulse_dmg" "$codex_pulse_final_tmp"
shasum -a 256 "$codex_pulse_dmg" > "$codex_pulse_work/SHA256SUMS.txt"
mv -f "$codex_pulse_final_tmp" "$codex_pulse_final_directory/Codex-Pulse-$codex_pulse_version.dmg"
printf '%s\n' "已签名、公证并附加凭证的安装包：$codex_pulse_final_directory/Codex-Pulse-$codex_pulse_version.dmg"
cat "$codex_pulse_work/SHA256SUMS.txt"
