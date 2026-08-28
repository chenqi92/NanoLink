#!/usr/bin/env bash
# Internal task: stop NanoOps development servers

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${GREEN}Stopping NanoOps Development Environment${NC}"

# Kill by saved PIDs
if [ -f /tmp/nanolink-backend.pid ]; then
    BACKEND_PID=$(cat /tmp/nanolink-backend.pid)
    if kill -0 $BACKEND_PID 2>/dev/null; then
        echo "Stopping backend (  PID: $BACKEND_PID)"
        kill $BACKEND_PID
    fi
    rm /tmp/nanolink-backend.pid
fi

if [ -f /tmp/nanolink-frontend.pid ]; then
    FRONTEND_PID=$(cat /tmp/nanolink-frontend.pid)
    if kill -0 $FRONTEND_PID 2>/dev/null; then
        echo "Stopping frontend (PID: $FRONTEND_PID)"
        kill $FRONTEND_PID
    fi
    rm /tmp/nanolink-frontend.pid
fi

# Fallback: kill by process name
pkill -f "nanolink-server" 2>/dev/null
pkill -f "vite.*web" 2>/dev/null

echo -e "${GREEN}Development servers stopped${NC}"
