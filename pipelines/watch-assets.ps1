$ErrorActionPreference = "Stop"

$staging  = "C:\app-logos"
$pipeline = "$HOME\fenix-assets\pipelines\push-assets.ps1"

Write-Host "👀 Watching: $staging"
Write-Host "🚀 Pipeline: $pipeline"
Write-Host "Drop an image into C:\app-logos to auto-push."

function Wait-ForFileReady([string]$path) {
  for ($i = 0; $i -lt 40; $i++) {
    try {
      $fs = [System.IO.File]::Open($path,'Open','Read','None')
      $fs.Close()
      return $true
    } catch {
      Start-Sleep -Milliseconds 350
    }
  }
  return $false
}

$fsw = New-Object System.IO.FileSystemWatcher
$fsw.Path = $staging
$fsw.Filter = "*.*"
$fsw.IncludeSubdirectories = $false
$fsw.EnableRaisingEvents = $true

Register-ObjectEvent -InputObject $fsw -EventName Created -SourceIdentifier "AssetCreated" -Action {
  $p = $Event.SourceEventArgs.FullPath
  Start-Sleep -Milliseconds 250

  if (Test-Path $p) {
    Write-Host "📦 Detected: $p"

    if (Wait-ForFileReady $p) {
      Write-Host "✅ File ready. Running pipeline..."
      powershell -NoProfile -ExecutionPolicy Bypass -File $using:pipeline
      Write-Host "🏁 Pipeline finished."
    } else {
      Write-Host "⚠️ File never became ready: $p"
    }
  }
} | Out-Null

while ($true) { Start-Sleep 2 }
