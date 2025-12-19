# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Prometheus metrics export support
- Alert rules and notifications
- Historical data storage integration

## [0.1.0] - 2025-12-19

### Added

#### Agent
- Initial release of NanoLink Agent written in Rust
- Cross-platform support (Linux, macOS, Windows)
- Comprehensive system monitoring:
  - CPU: usage, model, vendor, frequency, temperature, per-core stats
  - Memory: usage, type (DDR4/DDR5), speed, cached/buffers
  - Disk: usage, model, type (SSD/HDD/NVMe), I/O rates, IOPS, S.M.A.R.T. health
  - Network: throughput, MAC address, IP addresses, link speed
  - GPU: NVIDIA/AMD/Intel support with usage, VRAM, temperature, power
  - System: OS info, kernel, motherboard, BIOS, uptime
- WebSocket + Protocol Buffers communication
- 4-level permission system (READ_ONLY, BASIC_WRITE, SERVICE_CONTROL, SYSTEM_ADMIN)
- Ring buffer for 10-minute offline data caching
- Token-based authentication
- Command whitelist/blacklist
- Shell command execution with SuperToken

#### Java SDK
- NanoLinkServer with builder pattern
- WebSocket server based on Netty
- Agent connection management
- Metrics callback handling
- Embedded dashboard support
- Custom token validator support
- TLS support

#### Go SDK
- NanoLinkServer with configuration struct
- WebSocket server based on gorilla/websocket
- Agent connection management
- Metrics callback handling
- Embedded dashboard support
- Custom token validator support
- API endpoints for agents and health check

#### Python SDK
- Async NanoLinkServer with decorator-based callbacks
- WebSocket server based on websockets library
- Full type hints with dataclasses
- Agent connection management with command execution
- Metrics callback handling
- Support for Python 3.8+
- PyPI package distribution

#### Dashboard
- Vue 3 + Vite + TailwindCSS
- Real-time metrics display
- Server connection status
- CPU and memory usage charts
- Connected agents list
- Responsive design

#### CI/CD
- GitHub Actions workflows:
  - Test workflow for PR/Push
  - Release Agent workflow for multi-platform builds
  - SDK Release workflow triggered by VERSION file changes
- Cross-platform builds:
  - Linux x86_64, ARM64
  - macOS x86_64, ARM64 (Apple Silicon)
  - Windows x86_64
- Automatic GitHub Release creation

### Security
- TLS encryption for all communication
- Token authentication
- Command whitelist/blacklist
- Complete audit logging
- Dangerous commands require SuperToken and confirmation

## Links

- [GitHub Repository](https://github.com/chenqi92/NanoLink)
- [Documentation](https://github.com/chenqi92/NanoLink#readme)
- [Issues](https://github.com/chenqi92/NanoLink/issues)

[Unreleased]: https://github.com/chenqi92/NanoLink/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/chenqi92/NanoLink/releases/tag/v0.1.0
