# Dokploy Radar

A native macOS menu bar app for monitoring multiple Dokploy instances.

- Add one or more Dokploy instances with API tokens
- See deploying and recently updated services at the top of the menu bar list
- Open the companion app window for the full dashboard

## Development

Requires macOS 13+ and full Xcode.

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run
```

Or open `Package.swift` in Xcode and run the `DokployRadar` target.

## Packaging

Build a local app bundle, ZIP, and DMG with:

```bash
./Tools/package-release.sh
```

Artifacts land in `dist/<version>/`.

Optional environment variables:

- `VERSION=0.1.0`
- `BUILD_NUMBER=1`
- `APP_NAME="Dokploy Radar"`
- `BUNDLE_IDENTIFIER="com.mukhtharcm.dokployradar"`
- `SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)"`

The packager auto-generates the app icon and DMG background, and it installs `dmgbuild` into `.build/dmgbuild-venv` on first use if it is not already available.

## Notes

- The app polls configured Dokploy instances on an interval
- Tokens are stored locally in Application Support for this prototype
- Recent deployments currently mean deployments within the last hour
- macOS notifications only work from the packaged `.app`, not direct `swift run` launches
- Dokploy API research notes live in `Docs/dokploy-api-research.md`
