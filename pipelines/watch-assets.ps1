[CmdletBinding()]
param(
  [string]$StagingPath = 'C:\app-logos',
  [string]$PushScript = '',
  [string]$BasePushScript = '',
  [string]$LogPath = '',
  [int]$PollSeconds = 5,
  [int]$StableChecks = 5,
  [int]$StableDelayMs = 300
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
if ([string]::IsNullOrWhiteSpace($PushScript)) { $PushScript = Join-Path $scriptDir 'push-assets.pro.ps1' }
if ([string]::IsNullOrWhiteSpace($BasePushScript)) { $BasePushScript = Join-Path $scriptDir 'push-assets.ps1' }
if ([string]::IsNullOrWhiteSpace($LogPath)) { $LogPath = Join-Path $scriptDir 'logs\watch-assets.log' }

function Ensure-Folder([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
}

function Log([string]$Message) {
  Ensure-Folder (Split-Path -Path $LogPath -Parent)
  Add-Content -Path $LogPath -Value ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message)
}

function Test-FileStable([string]$Path) {
  $lastLen = -1
  $stable = 0
  for ($i=0; $i -lt 80; $i++) {
    try {
      $fi = Get-Item -LiteralPath $Path -ErrorAction Stop
      $len = $fi.Length
      $fs = [System.IO.File]::Open($Path,[System.IO.FileMode]::Open,[System.IO.FileAccess]::Read,[System.IO.FileShare]::Read)
      $fs.Close()

      if ($len -eq $lastLen) { $stable++ } else { $stable = 0 }
      $lastLen = $len
      if ($stable -ge $StableChecks) { return $true }
    } catch {
      $stable = 0
    }
    Start-Sleep -Milliseconds $StableDelayMs
  }
  return $false
}

Ensure-Folder $StagingPath
Ensure-Folder (Split-Path -Path $LogPath -Parent)
Log ("watcher start | staging={0} push={1}" -f $StagingPath, $PushScript)

$supported = @('.webp','.png','.jpg','.jpeg','.svg')

while ($true) {
  try {
    $files = Get-ChildItem -LiteralPath $StagingPath -File -ErrorAction SilentlyContinue | Where-Object { $supported -contains $_.Extension.ToLower() }

    if ($files -and $files.Count -gt 0) {
      $ready = $false
      foreach ($f in $files) {
        if (Test-FileStable -Path $f.FullName) { $ready = $true; break }
      }

      if ($ready) {
        Log ("detected {0} candidate file(s) | running pipeline" -f $files.Count)
        $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $PushScript -ConvertToWebp -WebpQuality 82 -StagingPath $StagingPath -BasePushScript $BasePushScript -ResizeWidths '256,512,1024,2048' 2>&1
        foreach ($line in $out) { Add-Content -Path $LogPath -Value ($line.ToString()) }

        if ($LASTEXITCODE -ne 0) { Log ("pipeline exit code={0}" -f $LASTEXITCODE) }
        Start-Sleep -Seconds 2
      }
    }
  } catch {
    Log ("ERROR: {0}" -f $_.Exception.Message)
    Start-Sleep -Seconds 2
  }

  Start-Sleep -Seconds $PollSeconds
}
