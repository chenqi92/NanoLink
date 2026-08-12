@echo off
REM Development server startup script for NanoLink (Windows)

setlocal enabledelayedexpansion

cd /d "%~dp0"

echo Starting NanoLink Development Environment

REM Check if backend binary exists
if not exist "build\nanolink-server.exe" (
    echo Error: Backend binary not found in build\
    echo Please run: cd apps\server ^&^& go build -o ..\..\build\nanolink-server.exe .\cmd
    exit /b 1
)

REM Set environment variables for backend
if "%NANOLINK_JWT_SECRET%"=="" (
    set "NANOLINK_JWT_SECRET=development-test-secret-key-32bytes-or-more-20260812"
)
if "%NANOLINK_ADMIN_USERNAME%"=="" (
    set "NANOLINK_ADMIN_USERNAME=admin"
)
if "%NANOLINK_ADMIN_PASSWORD%"=="" (
    set "NANOLINK_ADMIN_PASSWORD=admin123456"
)

REM Create config if not exists
if not exist "config.yaml" (
    echo Config file not found, copying from template
    copy apps\docker\config.yaml config.yaml >nul
    powershell -Command "(Get-Content config.yaml) -replace '/app/data/nanolink.db', './nanolink.db' | Set-Content config.yaml"
)

REM Check if old server is running and kill it
echo Checking for running servers...
for /f "tokens=2" %%a in ('tasklist ^| findstr /i "nanolink-server.exe"') do (
    echo Stopping old backend server (PID: %%a)
    taskkill /PID %%a /F >nul 2>&1
)

REM Start backend server
echo Starting backend server...
start "NanoLink Backend" /B build\nanolink-server.exe -config config.yaml > %TEMP%\nanolink-server.log 2>&1

REM Wait for backend to be ready
echo Waiting for backend to start...
timeout /t 3 /nobreak >nul

REM Check if backend is running
curl -s http://localhost:8080/api/health >nul 2>&1
if errorlevel 1 (
    echo Backend failed to start. Check %TEMP%\nanolink-server.log
    exit /b 1
)
echo Backend is ready!

REM Start frontend dev server
echo Starting frontend dev server...
cd apps\server\web
start "NanoLink Frontend" cmd /k "npm run dev"

timeout /t 3 /nobreak >nul

echo.
echo ========================================
echo NanoLink Development Environment Ready!
echo ========================================
echo.
echo Frontend: http://localhost:5173/dashboard
echo Backend API: http://localhost:8080/api
echo Admin credentials: %NANOLINK_ADMIN_USERNAME% / %NANOLINK_ADMIN_PASSWORD%
echo.
echo Logs:
echo   Backend:  type %TEMP%\nanolink-server.log
echo   Frontend: (see the separate window)
echo.
echo To stop: Close the frontend window and run: taskkill /F /IM nanolink-server.exe
echo.

REM Keep window open
pause
