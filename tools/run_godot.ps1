param([string]$Mode, [int]$Limit = 600, [string]$Extra = "")
# Runs Godot on the flesh-pit project with a time limit. Mode: import | script <path> | window <path>
$godot = 'C:\Users\fixme\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
$proj = 'C:\Users\fixme\Desktop\flesh-pit-main\game'
$log = Join-Path $proj ('.godot_run_' + $Mode + '.log')
if ($Mode -eq 'import') { $a = @('--headless', '--path', $proj, '--editor', '--import') }
elseif ($Mode -eq 'script') { $a = @('--headless', '--path', $proj, '--script', $Extra) }
else { $a = @('--path', $proj, '--windowed', '--resolution', '1280x720', '--script', $Extra) }
$p = Start-Process -FilePath $godot -ArgumentList $a -PassThru -NoNewWindow -RedirectStandardOutput $log -RedirectStandardError ($log + '.err')
$null = $p.Handle
if (-not $p.WaitForExit($Limit * 1000)) { taskkill /PID $p.Id /T /F | Out-Null; Write-Output "TIMEOUT"; }
Write-Output ("EXIT " + $p.ExitCode)
Get-Content $log -Tail 60
Get-Content ($log + '.err') -Tail 40
