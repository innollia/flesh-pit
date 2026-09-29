param([string]$Yaw, [string]$Pitch, [string]$X, [string]$Y, [string]$Z, [string]$Door = "")
$godot = 'C:\Users\fixme\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
$proj = 'C:\Users\fixme\Desktop\flesh-pit-main\game'
$a = @('--path', $proj, '--windowed', '--resolution', '1280x720', '--script', 'res://tools/_capture_debug.gd', '--', $Yaw, $Pitch, $X, $Y, $Z)
if ($Door -ne "") { $a += $Door }
$logDir = Join-Path $proj 'logs'
New-Item -ItemType Directory -Path $logDir -ErrorAction SilentlyContinue | Out-Null
$p = Start-Process -FilePath $godot -ArgumentList $a -PassThru -NoNewWindow -RedirectStandardOutput "$logDir\dbg.log" -RedirectStandardError "$logDir\dbg.err"
$null = $p.Handle
if (-not $p.WaitForExit(120000)) { taskkill /PID $p.Id /T /F | Out-Null; "TIMEOUT" }
Get-Content "$logDir\dbg.err" | Select-String 'ERROR|SCRIPT' | Select-Object -First 8
python "$proj\tools\capture_ascii.py" "$proj\captures\_debug.png" 100
