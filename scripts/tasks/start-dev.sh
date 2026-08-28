#!/usr/bin/env bash
# Development server startup script for NanoOps
# Works on macOS and Linux

set -e

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd)
cd "$REPO_ROOT"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting NanoOps Development Environment${NC}"

# Check if backend binary exists
if [ ! -f "build/nanolink-server" ] && [ ! -f "build/nanolink-server.exe" ]; then
    echo -e "${RED}Error: Backend binary not found in build/${NC}"
    echo "Please run: cd apps/server && go build -o ../../build/nanolink-server ./cmd"
    exit 1
fi

# Set environment variables for backend
export NANOLINK_JWT_SECRET="${NANOLINK_JWT_SECRET:-development-test-secret-key-32bytes-or-more-$(date +%s)}"
export NANOLINK_ADMIN_USERNAME="${NANOLINK_ADMIN_USERNAME:-admin}"
export NANOLINK_ADMIN_PASSWORD="${NANOLINK_ADMIN_PASSWORD:-admin123456}"

# Create config if not exists
if [ ! -f "config.yaml" ]; then
    echo -e "${YELLOW}Config file not found, copying from template${NC}"
    cp apps/docker/config.yaml config.yaml
    # Update storage path for local development
    if [[ "$OSTYPE" == "darwin"* ]] || [[ "$OSTYPE" == "linux-gnu"* ]]; then
        sed -i.bak 's|path: /app/data/nanolink.db|path: ./nanolink.db|' config.yaml
    fi
fi

# Start backend server
echo -e "${GREEN}Starting backend server...${NC}"
if [ -f "build/nanolink-server" ]; then
    BACKEND_BIN="./build/nanolink-server"
else
    BACKEND_BIN="./build/nanolink-server.exe"
fi

$BACKEND_BIN -config config.yaml > /tmp/nanolink-server.log 2>&1 &
BACKEND_PID=$!
echo -e "${GREEN}Backend started (PID: $BACKEND_PID)${NC}"

# Wait for backend to be ready
echo -e "${YELLOW}Waiting for backend to start...${NC}"
for i in {1..10}; do
    if curl -s http://localhost:8080/api/health > /dev/null 2>&1; then
        echo -e "${GREEN}Backend is ready!${NC}"
        break
    fi
    if [ $i -eq 10 ]; then
        echo -e "${RED}Backend failed to start. Check /tmp/nanolink-server.log${NC}"
        kill $BACKEND_PID 2>/dev/null || true
        exit 1
    fi
    sleep 1
done

# Start frontend dev server
echo -e "${GREEN}Starting frontend dev server...${NC}"
cd apps/server/web
npm run dev > /tmp/nanolink-vite.log 2>&1 &
FRONTEND_PID=$!
echo -e "${GREEN}Frontend started (PID: $FRONTEND_PID)${NC}"

# Wait for frontend to be ready
echo -e "${YELLOW}Waiting for frontend to start...${NC}"
sleep 3

echo ""
echo -e "${GREEN}✓ NanoOps Development Environment is running!${NC}"
echo ""
echo -e "${GREEN}Frontend:${NC} http://localhost:5173/dashboard"
echo -e "${GREEN}Backend API:${NC} http://localhost:8080/api"
echo -e "${GREEN}Admin credentials:${NC} $NANOLINK_ADMIN_USERNAME / $NANOLINK_ADMIN_PASSWORD"
echo ""
echo -e "${YELLOW}Logs:${NC}"
echo "  Backend:  tail -f /tmp/nanolink-server.log"
echo "  Frontend: tail -f /tmp/nanolink-vite.log"
echo ""
echo -e "${YELLOW}To stop:${NC}"
echo "  kill $BACKEND_PID $FRONTEND_PID"
echo "  Or press Ctrl+C and run: pkill -f nanolink-server; pkill -f vite"
echo ""

# Save PIDs for cleanup script
echo $BACKEND_PID > /tmp/nanolink-backend.pid
echo $FRONTEND_PID > /tmp/nanolink-frontend.pid
