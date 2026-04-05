# Dokploy Radar

A native macOS menu bar app for monitoring multiple Dokploy instances.

- Add one or more Dokploy instances with API tokens
- See deploying and recently deployed apps at the top of the menu bar list
- Open the companion app window for the full dashboard

## Development

Requires macOS 13+ and full Xcode.

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run
```

Or open `Package.swift` in Xcode and run the `DokployRadar` target.

## Notes

- The app polls configured Dokploy instances on an interval
- Tokens are stored locally in Application Support for this prototype
- Recent deployments currently mean deployments within the last hour
