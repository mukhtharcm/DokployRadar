#!/bin/zsh

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"

app_name="${APP_NAME:-Dokploy Radar}"
executable_name="${EXECUTABLE_NAME:-DokployRadar}"
default_bundle_identifier="com.mukhtharcm.dokployradar"
bundle_identifier="${BUNDLE_IDENTIFIER:-$default_bundle_identifier}"
icon_file_name="${ICON_FILE_NAME:-AppIcon}"
version="${VERSION:-0.1.0}"
build_number="${BUILD_NUMBER:-1}"
developer_dir="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
swiftpm_home="$project_root/.home"
codesign_timestamp="${CODESIGN_TIMESTAMP:-1}"
dmgbuild_version="${DMGBUILD_VERSION:-1.6.7}"

dist_root="$project_root/dist/$version"
app_path="$dist_root/$app_name.app"
zip_name="${app_name// /-}-${version}.zip"
dmg_name="${app_name// /-}-${version}.dmg"
zip_path="$dist_root/$zip_name"
dmg_path="$dist_root/$dmg_name"
package_workspace="$project_root/.build/package-release/$version"
plist_template="$project_root/Packaging/Info.plist.template"
icon_script_path="$project_root/Tools/generate-app-icon.swift"
dmg_background_script_path="$project_root/Tools/generate-dmg-background.swift"
dmgbuild_settings_path="$project_root/Packaging/dmgbuild-settings.py"
dmgbuild_venv="$project_root/.build/dmgbuild-venv"
dmgbuild_bin="$dmgbuild_venv/bin/dmgbuild"

ensure_dmgbuild() {
    if command -v dmgbuild >/dev/null 2>&1; then
        dmgbuild_cmd="$(command -v dmgbuild)"
        return
    fi

    if [[ -x "$dmgbuild_bin" ]]; then
        dmgbuild_cmd="$dmgbuild_bin"
        return
    fi

    echo "Installing dmgbuild $dmgbuild_version..."
    python3 -m venv "$dmgbuild_venv"
    "$dmgbuild_venv/bin/python" -m pip install --quiet "dmgbuild==$dmgbuild_version"
    dmgbuild_cmd="$dmgbuild_bin"
}

generate_icns() {
    local preview_png="$package_workspace/${icon_file_name}-preview.png"
    local iconset_dir="$package_workspace/${icon_file_name}.iconset"
    generated_icns_path="$package_workspace/${icon_file_name}.icns"

    swift "$icon_script_path" "$preview_png"
    rm -rf "$iconset_dir"
    mkdir -p "$iconset_dir"

    local -a icon_specs=(
        "icon_16x16.png:16"
        "icon_16x16@2x.png:32"
        "icon_32x32.png:32"
        "icon_32x32@2x.png:64"
        "icon_128x128.png:128"
        "icon_128x128@2x.png:256"
        "icon_256x256.png:256"
        "icon_256x256@2x.png:512"
        "icon_512x512.png:512"
        "icon_512x512@2x.png:1024"
    )

    local spec name size
    for spec in "${icon_specs[@]}"; do
        name="${spec%%:*}"
        size="${spec##*:}"
        sips -s format png -z "$size" "$size" "$preview_png" --out "$iconset_dir/$name" >/dev/null
    done

    iconutil -c icns "$iconset_dir" -o "$generated_icns_path"
}

export DEVELOPER_DIR="$developer_dir"
export SWIFTPM_MODULECACHE_OVERRIDE="$project_root/.build/module-cache"
export CLANG_MODULE_CACHE_PATH="$project_root/.build/clang-module-cache"

mkdir -p "$swiftpm_home" "$project_root/.build/module-cache" "$project_root/.build/clang-module-cache" "$package_workspace"

if [[ ! -f "$plist_template" ]]; then
    echo "Missing plist template: $plist_template" >&2
    exit 1
fi

if [[ ! -f "$icon_script_path" ]]; then
    echo "Missing icon generator: $icon_script_path" >&2
    exit 1
fi

if [[ ! -f "$dmg_background_script_path" ]]; then
    echo "Missing DMG background generator: $dmg_background_script_path" >&2
    exit 1
fi

echo "Building release binary..."
env HOME="$swiftpm_home" swift build -c release >/dev/null
bin_dir="$(env HOME="$swiftpm_home" swift build -c release --show-bin-path)"

binary_path="$bin_dir/$executable_name"
resource_bundle_path="$bin_dir/${executable_name}_${executable_name}.bundle"

if [[ ! -f "$binary_path" ]]; then
    echo "Missing release binary: $binary_path" >&2
    exit 1
fi

generate_icns

rm -rf "$dist_root"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"

cp "$binary_path" "$app_path/Contents/MacOS/$executable_name"
chmod +x "$app_path/Contents/MacOS/$executable_name"
cp "$generated_icns_path" "$app_path/Contents/Resources/${icon_file_name}.icns"

if [[ -d "$resource_bundle_path" ]]; then
    cp -R "$resource_bundle_path" "$app_path/Contents/Resources/"
fi

sed \
    -e "s|__APP_NAME__|$app_name|g" \
    -e "s|__EXECUTABLE_NAME__|$executable_name|g" \
    -e "s|__BUNDLE_IDENTIFIER__|$bundle_identifier|g" \
    -e "s|__ICON_FILE__|$icon_file_name|g" \
    -e "s|__VERSION__|$version|g" \
    -e "s|__BUILD_NUMBER__|$build_number|g" \
    "$plist_template" > "$app_path/Contents/Info.plist"

if [[ -z "${SIGNING_IDENTITY:-}" ]]; then
    identities="$(security find-identity -v -p codesigning 2>/dev/null | grep 'Developer ID Application:' || true)"
    identity_count="$(printf '%s\n' "$identities" | sed '/^$/d' | wc -l | tr -d ' ')"

    if [[ "$identity_count" == "1" ]]; then
        signing_identity="$(printf '%s\n' "$identities" | sed -E 's/.*\"([^\"]+)\".*/\1/')"
        echo "Auto-detected signing identity: $signing_identity"
    else
        signing_identity=""
    fi
else
    signing_identity="$SIGNING_IDENTITY"
fi

if [[ -n "${signing_identity:-}" ]]; then
    echo "Signing app bundle with identity: $signing_identity"

    if [[ "$codesign_timestamp" == "0" ]]; then
        timestamp_args=(--timestamp=none)
    else
        timestamp_args=(--timestamp)
    fi

    codesign \
        --force \
        --deep \
        --options runtime \
        "${timestamp_args[@]}" \
        --sign "$signing_identity" \
        "$app_path"
fi

rm -f "$zip_path" "$dmg_path"

echo "Creating zip archive..."
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$zip_path"

echo "Creating dmg image..."
ensure_dmgbuild
dmg_background_path="$package_workspace/${app_name// /-}-dmg-background.png"
swift "$dmg_background_script_path" "$dmg_background_path"
"$dmgbuild_cmd" \
    -s "$dmgbuild_settings_path" \
    "$app_name" \
    "$dmg_path" \
    -D app_path="$app_path" \
    -D icon_path="$generated_icns_path" \
    -D background_path="$dmg_background_path" \
    -D app_name="$app_name" >/dev/null

echo
echo "Release artifacts:"
echo "  App: $app_path"
echo "  ZIP: $zip_path"
echo "  DMG: $dmg_path"
echo
if [[ -n "${signing_identity:-}" ]]; then
    echo "App bundle was signed with: $signing_identity"
else
    echo "Unsigned builds may trigger Gatekeeper on other Macs."
    echo "Set SIGNING_IDENTITY to produce a Developer ID signed bundle before distribution."
fi
