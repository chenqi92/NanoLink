# NanoLink Android

Native Android client for NanoLink, built with Jetpack Compose.

## Requirements

- Android Studio Ladybug or later
- Android SDK 26+ (API level 26, Android 8.0)
- Kotlin 2.1+
- Gradle 8.11+

## Project Structure

```
app/src/main/
├── java/com/nanolink/app/
│   ├── MainActivity.kt              # Application entry point
│   ├── data/
│   │   ├── model/                   # Data models (Agent, ServerConnection, Metrics, etc.)
│   │   ├── network/                 # REST and WebSocket services
│   │   ├── storage/                 # Secure storage, preferences, persistence
│   │   └── notification/            # Local notification service
│   ├── localization/
│   │   └── L10n.kt                  # JSON-based i18n engine
│   ├── state/
│   │   ├── AppViewModel.kt          # Main application state
│   │   └── ThemeViewModel.kt        # Theme preferences
│   └── ui/
│       ├── NanoShell.kt             # Five-tab navigation shell
│       ├── design/                  # Design system (tokens, components, charts)
│       └── screens/                 # Dashboard, Nodes, Terminal, Activity, Settings
├── res/
│   ├── values/
│   │   ├── strings.xml              # App name and minimal static strings
│   │   ├── colors.xml               # Material baseline colors
│   │   └── themes.xml               # Material 3 base theme
│   └── xml/
│       └── network_security_config.xml  # Permits HTTP for self-hosted servers
└── assets/
    └── i18n/
        ├── en.json                  # English localization table
        └── zh.json                  # Chinese localization table
```

## Architecture

- **MVVM**: `AppViewModel` holds all application state and orchestrates services
- **StateFlow**: Reactive state updates via Kotlin Flow
- **Jetpack Compose**: Declarative UI with Material 3 components
- **Retrofit + OkHttp**: REST API and WebSocket communication
- **EncryptedSharedPreferences**: Secure token storage
- **AndroidX DataStore**: User preferences
- **Navigation Compose**: Type-safe screen navigation

## Building

```bash
./gradlew assembleDebug
```

## Running

Open the project in Android Studio and run on a device or emulator (API 26+).

The app connects to NanoLink servers via HTTP/HTTPS + WebSocket. Network security configuration permits cleartext traffic for local/self-hosted deployments.

## Features Implemented

### Foundation
- ✅ Models: Agent, ServerConnection, Metrics, Alerts, Audit, Chat
- ✅ REST client with Retrofit
- ✅ WebSocket client with OkHttp
- ✅ Secure storage (EncryptedSharedPreferences + Keychain fallback)
- ✅ Preferences via DataStore
- ✅ Local notifications (NotificationService)
- ✅ JSON localization (en/zh)
- ✅ Theme system (light/dark/system, iOS/Material styles, compact mode)

### Design System
- ✅ Tokens (colors, spacing, radii)
- ✅ Components (buttons, cards, tiles, badges, status dots, meters)
- ✅ Charts (sparkline, line chart, donut gauge, core matrix, KPI tiles)
- ✅ Dual-theme support (light/dark with automatic Material/iOS palette switching)
- ✅ iOS-style translucent tab bar with glass border

### Navigation
- ✅ Five-tab shell: Dashboard, Nodes, Terminal, Activity, Settings
- ✅ Badge count on Activity tab for unacknowledged alerts
- ✅ Material 3 NavigationBar + iOS-style custom tab bar (theme-aware)

### Screens
- 🚧 Dashboard (skeleton)
- 🚧 Nodes (skeleton)
- 🚧 Terminal (skeleton)
- 🚧 Activity (skeleton)
- 🚧 Settings (skeleton)

## Next Steps

1. Implement Dashboard screen (KPI tiles, sparklines, agent summary)
2. Implement Nodes screen (agent list, detail view, command actions)
3. Implement Terminal screen (WebSocket shell, command history, themes)
4. Implement Activity screen (alerts list, audit log, acknowledgment)
5. Implement Settings screen (server management, theme/language, preferences)
6. Add QR scanning (CameraX + ML Kit Barcode)
7. Add QR generation (ZXing)
8. Add authentication screens (add server, pairing, reauth)
9. Add permission-aware UI (hide/disable features based on agent level)
10. Add pull-to-refresh and empty states

## License

Proprietary - NanoLink
