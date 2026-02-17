$staging = "C:\app-logos"
$pipeline = "$HOME\fenix-assets\pipelines\push-assets.ps1"

Write-Host "Watching C:\app-logos..."

$fsw = New-Object System.IO.FileSystemWatcher
$fsw.Path = $staging
$fsw.Filter = "*.*"
$fsw.EnableRaisingEvents = $true

Register-ObjectEvent $fsw Created -Action {
    Start-Sleep 2
    powershell -ExecutionPolicy Bypass -File $pipeline
}

while ($true) { Start-Sleep 5 }
