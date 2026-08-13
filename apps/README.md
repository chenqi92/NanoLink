# NanoLink Applications

Complete standalone applications for monitoring servers with NanoLink.

## Applications

| Application | Platform | Stack | Description |
|-------------|----------|-------|-------------|
| [Server](./server) | Linux/Docker | Go + React/Vite | Web-based monitoring dashboard |
| [Desktop](./desktop) | Windows/macOS/Linux | Flutter | Desktop application |
| [Desktop](./desktop) | Android | Flutter | APK, same codebase as desktop |
| [iOS](./ios) | iOS/iPadOS | SwiftUI | Native Xcode project (`NanoLink.xcodeproj`) |

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    NanoLink Applications                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │  Linux Server   │  │ Desktop/Android │  │  iOS / iPadOS   │  │
│  │  (Docker/Web)   │  │   (Flutter)     │  │   (SwiftUI)     │  │
│  └────────┬────────┘  └────────┬────────┘  └────────┬────────┘  │
│           │                    │                     │           │
│           └────────────────────┴─────────────────────┘           │
│                                │                                  │
│                    ┌───────────▼───────────┐                     │
│                    │   NanoLink Server     │                     │
│                    │  (Go/WebSocket/API)   │                     │
│                    └───────────┬───────────┘                     │
│                                │                                  │
└────────────────────────────────┼─────────────────────────────────┘
                                 │
                    WebSocket + Protocol Buffers
                                 │
         ┌───────────────────────┼───────────────────────┐
         ▼                       ▼                       ▼
    ┌─────────┐            ┌─────────┐            ┌─────────┐
    │ Agent 1 │            │ Agent 2 │            │ Agent N │
    └─────────┘            └─────────┘            └─────────┘
```

## Quick Start

### Docker (Recommended for Linux)

```bash
# Using docker-compose
cd docker
docker-compose up -d

# Or using pre-built image
docker run -d -p 9100:9100 -p 8080:8080 ghcr.io/chenqi92/nanolink-server:latest
```

### Desktop / Mobile Application

Download from [Releases](https://github.com/chenqi92/NanoLink/releases):

- **Windows**: `NanoLink-Windows-<version>.zip`
- **macOS Intel**: `NanoLink-macOS-Intel-<version>.dmg`
- **macOS Apple Silicon**: `NanoLink-macOS-AppleSilicon-<version>.dmg`
- **Linux**: `NanoLink-Linux-<version>.tar.gz`
- **Android**: `NanoLink-Android-<version>.apk`
- **iOS**: `NanoLink-iOS-<version>-unsigned.ipa` (unsigned, for sideloading)

## Building

### Server Image (multi-arch)

```bash
cd docker
docker-compose -f docker-compose.build.yml build
```

This builds the `linux/amd64` + `linux/arm64` server image. Desktop, Android and
iOS artifacts are built per-platform by `.github/workflows/apps-release.yml`.

### Build Specific Platform

```bash
# Linux server
cd server
go build -o nanolink-server ./cmd

# Desktop / Android (requires Flutter 3.44.4, Dart SDK ^3.5.0)
cd desktop
flutter pub get
flutter build windows --release   # or: macos / linux / apk

# iOS / iPadOS (requires macOS with Xcode)
xcodebuild -project ios/NanoLink.xcodeproj -scheme NanoLink \
  -configuration Release -sdk iphoneos build
```

## Configuration

### Server Configuration

```yaml
# config.yaml
server:
  http_port: 8080
  ws_port: 9100

auth:
  enabled: true
  tokens:
    - token: "admin-token"
      permission: 3
    - token: "read-token"
      permission: 0

storage:
  type: sqlite  # sqlite, postgres, mysql
  path: ./data/nanolink.db

dashboard:
  enabled: true
```

### Desktop / Mobile Configuration

No config file is written. Server connection metadata (id, name, url, username,
lastConnected) is persisted through `shared_preferences` under the key
`nanolink_servers`; the `token` / `userToken` secrets are stored separately in
`flutter_secure_storage` (Windows Credential Manager, macOS/iOS Keychain, Android
Keystore, Linux libsecret), keyed by server id.

The native iOS/iPadOS app uses the same split: metadata in `UserDefaults`, secrets in the
iOS Keychain (`Services/KeychainStore.swift`).

## License

MIT License - see [LICENSE](../LICENSE) for details.
