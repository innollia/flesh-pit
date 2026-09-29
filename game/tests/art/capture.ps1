param([string[]]$Names)
$G = 'C:\Users\fixme\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
$game = 'C:\Users\fixme\Desktop\flesh-pit-main\game'
$lock = 'C:\projects\_locks\fleshpit-godot.lock'
New-Item -ItemType Directory -Force C:\projects\_locks | Out-Null
$w = 0; while ((Test-Path $lock) -and $w -lt 120) { Start-Sleep 5; $w++ }
Set-Content $lock "art-worker $(Get-Date -Format o)"
$Names = $Names -split ","
try {
  foreach ($n in $Names) {
    $dir = "$game\captures\art\_frames\$n"
    Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force $dir | Out-Null
    $p = Start-Process -FilePath $G -ArgumentList @('--path',$game,'--resolution','960x720','--write-movie',"$dir\f.png",'--fixed-fps','10','--quit-after','14','res://tests/art/art_capture.tscn','--',$n) -PassThru -NoNewWindow -RedirectStandardOutput "$dir\log.txt" -RedirectStandardError "$dir\err.txt"
    if (-not $p.WaitForExit(120000)) { taskkill /T /F /PID $p.Id | Out-Null }
    $last = Get-ChildItem $dir -Filter 'f*.png' | Sort-Object Name | Select-Object -Last 1
    if ($last) { Copy-Item $last.FullName "$game\captures\art\$n.png" -Force; "OK $n" } else { "NOFRAME $n"; Get-Content "$dir\err.txt" -Tail 15; Get-Content "$dir\log.txt" -Tail 15 }
    Select-String "$dir\err.txt","$dir\log.txt" -Pattern 'ERROR|SCRIPT ERROR|Parse Error' | Select-Object -First 8 | % Line
  }
} finally { Remove-Item $lock -Force -ErrorAction SilentlyContinue }