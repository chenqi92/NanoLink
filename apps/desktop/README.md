# NanoLink Desktop

Cross-platform desktop application for monitoring NanoLink servers.

## Features

- Multi-server management
- Real-time metrics visualization
- System tray integration
- Cross-platform (Windows, macOS)

## Prerequisites

- [Node.js](https://nodejs.org/) (v18+)
- [Rust](https://www.rust-lang.org/tools/install) (latest stable)
- Platform-specific dependencies:
  - **Windows**: MSVC build tools
  - **macOS**: Xcode Command Line Tools

## Development

```bash
# Install dependencies
npm install

# Run in development mode
npm run tauri dev
```

## Building

```bash
# Build for current platform
npm run tauri build
```

Build outputs:
- **Windows**: `src-tauri/target/release/bundle/msi/NanoLink_*.msi`
- **macOS**: `src-tauri/target/release/bundle/dmg/NanoLink_*.dmg`

## Configuration

Settings are stored in:
- **Windows**: `%APPDATA%\NanoLink\config.json`
- **macOS**: `~/Library/Application Support/NanoLink/config.json`

## Usage

1. Launch the application
2. Click "+" to add a NanoLink server
3. Enter the WebSocket URL (e.g., `ws://localhost:9100`)
4. Enter your authentication token (if required)
5. Click on the server to connect

## System Tray

The application minimizes to the system tray:
- **Left-click** on tray icon: Show window
- **Right-click** on tray icon: Show menu

## License

MIT License
