@echo off
rem flesh-pit with the reward-scale play log (docs/operations.md, FP_PLAY_LOG).
rem Each run writes a new CSV in playlogs\ (the log overwrites its file, so
rem the name carries the start time). The log never touches the save slot.
setlocal
cd /d "%~dp0"
if not exist playlogs mkdir playlogs
for /f %%t in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss"') do set STAMP=%%t
set "FP_PLAY_LOG=%~dp0playlogs\play-%STAMP%.csv"
echo Play log: %FP_PLAY_LOG%
godot --path game
echo.
echo Reading the log with the reward scale...
python -X utf8 tools\economy\reward_scale.py --log "%FP_PLAY_LOG%"
pause
