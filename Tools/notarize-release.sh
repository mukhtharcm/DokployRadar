#!/bin/zsh

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"

app_name="${APP_NAME:-Dokploy Radar}"
version="${VERSION:-0.1.0}"
dist_root="$project_root/dist/$version"
app_path="$dist_root/$app_name.app"
dmg_path="$dist_root/${app_name// /-}-${version}.dmg"

if [[ ! -d "$app_path" ]]; then
    echo "Missing app bundle: $app_path" >&2
    echo "Run ./Tools/package-release.sh first." >&2
    exit 1
fi

if [[ ! -f "$dmg_path" ]]; then
    echo "Missing DMG: $dmg_path" >&2
    echo "Run ./Tools/package-release.sh first." >&2
    exit 1
fi

auth_args=()

if [[ -n "${NOTARYTOOL_PROFILE:-}" ]]; then
    auth_args+=(--keychain-profile "$NOTARYTOOL_PROFILE")
else
    : "${APPLE_ID:?Set APPLE_ID or NOTARYTOOL_PROFILE}"
    : "${APP_SPECIFIC_PASSWORD:?Set APP_SPECIFIC_PASSWORD or NOTARYTOOL_PROFILE}"
    : "${TEAM_ID:?Set TEAM_ID or NOTARYTOOL_PROFILE}"
    auth_args+=(--apple-id "$APPLE_ID" --team-id "$TEAM_ID" --password "$APP_SPECIFIC_PASSWORD")
fi

submission_json="$(mktemp)"
notary_log="$dist_root/notary-log.json"

cleanup() {
    rm -f "$submission_json"
}
trap cleanup EXIT

echo "Submitting DMG for notarization..."
xcrun notarytool submit "$dmg_path" --wait --output-format json "${auth_args[@]}" > "$submission_json"

submission_id="$(/usr/bin/plutil -extract id raw -o - "$submission_json")"
submission_status="$(/usr/bin/plutil -extract status raw -o - "$submission_json")"

echo "Submission ID: $submission_id"
echo "Status: $submission_status"

if [[ "$submission_status" != "Accepted" ]]; then
    echo "Fetching notarization log..."
    xcrun notarytool log "$submission_id" "${auth_args[@]}" "$notary_log" || true
    echo "Notarization failed. Log saved to: $notary_log" >&2
    exit 1
fi

echo "Fetching notarization log..."
xcrun notarytool log "$submission_id" "${auth_args[@]}" "$notary_log"

echo "Stapling notarization tickets..."
xcrun stapler staple "$app_path"
xcrun stapler staple "$dmg_path"

echo "Validating stapled artifacts..."
xcrun stapler validate "$app_path"
xcrun stapler validate "$dmg_path"
spctl -a -t exec -vv "$app_path"

echo
echo "Notarization complete:"
echo "  App: $app_path"
echo "  DMG: $dmg_path"
echo "  Log: $notary_log"
