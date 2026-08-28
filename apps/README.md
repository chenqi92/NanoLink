# NanoOps Applications

Complete standalone applications for monitoring servers with NanoOps.

## Applications

| Application | Platform | Stack | Description |
|-------------|----------|-------|-------------|
| [Server](./server) | Linux/Docker | Go + React/Vite | Web-based monitoring dashboard |
| [Android](./android) | Android | Kotlin + Jetpack Compose | Native Android project |
| [Apple](./ios) | iOS/iPadOS/macOS | SwiftUI | Native Xcode project with Mac Catalyst support |

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    NanoOps Applications                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │  Linux Server   │  │     Android     │  │ Apple Platforms │  │
│  │  (Docker/Web)   │  │    (Compose)    │  │   (SwiftUI)     │  │
│  └────────┬────────┘  └────────┬────────┘  └────────┬────────┘  │
│           │                    │                     │           │
│           └────────────────────┴─────────────────────┘           │
│                                │                                  │
│                    ┌───────────▼───────────┐                     │
│                    │   NanoOps Server     │                     │
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

### Native Applications

Download from [Releases](https://github.com/chenqi92/NanoLink/releases):

- **macOS**: `NanoOps-macOS-<version>.zip`
- **Android**: `NanoOps-Android-<version>.apk`
- **iOS**: `NanoOps-iOS-<version>-unsigned.ipa` (unsigned, for sideloading)

## Building

### Server Image (multi-arch)

```bash
cd docker
docker-compose -f docker-compose.build.yml build
```

This builds the `linux/amd64` + `linux/arm64` server image. Android and Apple
artifacts are built per-platform by `.github/workflows/apps-release.yml`.

### Build Specific Platform

```bash
# Linux server
cd server
go build -o nanolink-server ./cmd

# Android (requires JDK 17 and Android SDK)
cd android
./gradlew assembleRelease

# iOS / iPadOS (requires Xcode)
xcodebuild -project ios/NanoOps.xcodeproj -scheme NanoOps \
  -configuration Release -sdk iphoneos build

# macOS through Mac Catalyst
xcodebuild -project ios/NanoOps.xcodeproj -scheme NanoOps \
  -configuration Release \
  -destination "platform=macOS,variant=Mac Catalyst" build
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

### Native Application Configuration

The Android app stores preferences with DataStore and secrets with Android
Keystore. The Apple app stores metadata in `UserDefaults` and secrets in Keychain
(`Services/KeychainStore.swift`).

## License

MIT License - see [LICENSE](../LICENSE) for details.
