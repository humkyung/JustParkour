@echo off
where love >nul 2>&1
if %errorlevel%==0 (
    love .
) else if exist "C:\Program Files\LOVE\love.exe" (
    "C:\Program Files\LOVE\love.exe" .
) else (
    echo LOVE2D not found. Install from https://love2d.org/ or add love to PATH.
    pause
)
