# NanoLink Development Setup

## Quick Start

### Prerequisites

- Go 1.21+
- Node.js 18+
- npm or yarn

### Development Mode (Recommended)

Development mode runs the frontend with hot-reload and proxies API requests to the backend.

**macOS/Linux:**
```bash
./scripts/nanoops.sh start
```

**Windows:**
```bat
scripts\nanoops.bat start
```

You can also double-click `scripts\nanoops.bat` and choose **Start development environment**. It will automatically:

- install or synchronize the Web dependencies;
- rebuild and start the local Server when no healthy API is already running;
- start Vite with hot reload on a fixed port;
- wait for both services to become healthy;
- open the dashboard in the default browser.

If port 8080 already exposes a healthy NanoOps API, the script safely reuses
it. If port 5173 is occupied, Vite automatically uses the next free port up to
5183 and the script opens the correct URL.

Use `scripts\nanoops.bat start -NoBrowser` when you do not want it to open a browser, or
`scripts\nanoops.bat start -SkipBackendBuild` to reuse the existing Server binary.

Then open http://localhost:5173/dashboard

**Default credentials:** admin / admin123456

### Stop Development Servers

**macOS/Linux:**
```bash
./scripts/nanoops.sh stop
```

**Windows:**
```bat
scripts\nanoops.bat stop
```

## Production Build

### Backend with Embedded Frontend

To build a single binary with embedded web UI:

1. Build frontend:
```bash
cd apps/server/web
npm install
npm run build
```

2. Build backend (requires CGO for SQLite):

**macOS/Linux:**
```bash
cd apps/server
CGO_ENABLED=1 go build -o ../../build/nanolink-server ./cmd
```

**Windows (requires TDM-GCC or MinGW):**
```powershell
cd apps\server
$env:CGO_ENABLED=1
go build -o ..\..\build\nanolink-server.exe .\cmd
```

> **Note:** Windows requires a C compiler (gcc) for SQLite support. Install [TDM-GCC](https://jmeubank.github.io/tdm-gcc/) or use WSL.

3. Run:
```bash
export NANOLINK_JWT_SECRET="your-secret-key-at-least-32-bytes-long"
export NANOLINK_ADMIN_USERNAME="admin"
export NANOLINK_ADMIN_PASSWORD="your-password"
./build/nanolink-server -config config.yaml
```

## Configuration

Copy the example config:
```bash
cp apps/docker/config.yaml config.yaml
```

Key settings for development:
```yaml
storage:
  type: sqlite  # or 'memory' for testing
  path: ./nanolink.db

server:
  http_port: 8080
  ws_port: 9100
  grpc_port: 39100
  mode: debug  # or 'release' for production
```

## Environment Variables

Required for backend:
- `NANOLINK_JWT_SECRET`: JWT signing key (min 32 bytes)
- `NANOLINK_ADMIN_USERNAME`: Initial admin username
- `NANOLINK_ADMIN_PASSWORD`: Initial admin password (min 8 chars)

Optional:
- `NANOLINK_EXTERNAL_URL`: Public URL for device pairing
- `NANOLINK_ALLOW_PUBLIC_REGISTRATION`: Allow first user signup

## Troubleshooting

### Backend fails with "go-sqlite3 requires cgo"

**Solution:** Use development mode (runs backend and frontend separately), or install a C compiler:
- **Windows:** Install [TDM-GCC](https://jmeubank.github.io/tdm-gcc/)
- **macOS:** `xcode-select --install`
- **Linux:** `sudo apt install build-essential` (Debian/Ubuntu) or `sudo yum install gcc` (RHEL/CentOS)

### Frontend shows old code after changes

If using the production binary, you need to:
1. Rebuild frontend: `cd apps/server/web && npm run build`
2. Rebuild backend: `cd apps/server && go build -o ../../build/nanolink-server ./cmd`

Development mode (recommended) has hot-reload and doesn't require rebuilding.

### Port already in use

Check and kill existing processes:
```bash
# macOS/Linux
lsof -i :8080 | grep LISTEN | awk '{print $2}' | xargs kill
lsof -i :5173 | grep LISTEN | awk '{print $2}' | xargs kill

# Windows
netstat -ano | findstr :8080
taskkill /PID <PID> /F
```

## Project Structure

```
NanoLink/
├── apps/
│   ├── server/          # Go backend
│   │   ├── cmd/         # Main entry point
│   │   ├── internal/    # Business logic
│   │   ├── web/         # Frontend source
│   │   │   ├── src/     # React + TypeScript
│   │   │   └── dist/    # Built assets (embedded in Go binary)
│   │   └── embed.go     # Embeds web/dist/* into binary
│   └── docker/          # Docker configs
├── build/               # Compiled binaries
├── config.yaml          # Server configuration
└── start-dev.*          # Development startup scripts
```

## Development Workflow

1. **Frontend changes:**
   - Development mode: Changes auto-reload at http://localhost:5173
   - Production: Rebuild frontend + backend, restart server

2. **Backend changes:**
   - Stop server: `./scripts/nanoops.sh stop` or Ctrl+C
   - Rebuild: `cd apps/server && go build -o ../../build/nanolink-server ./cmd`
   - Restart: `./scripts/nanoops.sh start`

3. **Database schema changes:**
   - GORM auto-migrates on startup
   - Check `internal/database/*.go` for models
   - Delete `nanolink.db` to reset (dev only)
