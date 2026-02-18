[CmdletBinding()]
param(
  [string]$StagingPath = 'C:\app-logos',
  [string]$PushScript = '',
  [string]$BasePushScript = '',
  [string]$LogPath = '',
  [int]$DebounceMs = 1200,
  [int]$StableChecks = 5,
  [int]$StableDelayMs = 300
)

$ErrorActionPreference = 'Stop'

# Single-instance lock to prevent duplicate watcher processes.
$mutexName = 'Global\FENIX.AssetPipeline.Watcher'
$createdNew = $false
$mutex = New-Object System.Threading.Mutex($true, $mutexName, [ref]$createdNew)
if (-not $createdNew) { exit 0 }

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

$supported = @('.webp','.png','.jpg','.jpeg','.svg')
$busy = $false

$fsw = New-Object System.IO.FileSystemWatcher
$fsw.Path = $StagingPath
$fsw.Filter = '*.*'
$fsw.IncludeSubdirectories = $false
$fsw.NotifyFilter = [System.IO.NotifyFilters]'FileName, LastWrite, Size'
$fsw.EnableRaisingEvents = $true

Register-ObjectEvent -InputObject $fsw -EventName Created -SourceIdentifier 'FENIX.AssetDrop' | Out-Null

Log ("watcher start | staging={0} push={1}" -f $StagingPath, $PushScript)

try {
  while ($true) {
    $evt = Wait-Event -SourceIdentifier 'FENIX.AssetDrop' -Timeout 30
    if (-not $evt) { continue }

    # Drain queued burst events.
    Remove-Event -SourceIdentifier 'FENIX.AssetDrop' -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds $DebounceMs

    if ($busy) { continue }
    $busy = $true

    try {
      $files = Get-ChildItem -LiteralPath $StagingPath -File -ErrorAction SilentlyContinue | Where-Object { $supported -contains $_.Extension.ToLower() }
      if (-not $files -or $files.Count -eq 0) { continue }

      $ready = $false
      foreach ($f in $files) {
        if (Test-FileStable -Path $f.FullName) { $ready = $true; break }
      }
      if (-not $ready) { continue }

      Log ("detected {0} candidate file(s) | running pipeline" -f $files.Count)
      $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $PushScript -ConvertToWebp -WebpQuality 82 -StagingPath $StagingPath -BasePushScript $BasePushScript -ResizeWidths '256,512,1024,2048' 2>&1
      foreach ($line in $out) { Add-Content -Path $LogPath -Value ($line.ToString()) }

      if ($LASTEXITCODE -ne 0) { Log ("pipeline exit code={0}" -f $LASTEXITCODE) }

      # Clear any generated-event backlog after processing.
      Remove-Event -SourceIdentifier 'FENIX.AssetDrop' -ErrorAction SilentlyContinue
    } catch {
      Log ("ERROR: {0}" -f $_.Exception.Message)
    } finally {
      $busy = $false
    }
  }
} finally {
  Unregister-Event -SourceIdentifier 'FENIX.AssetDrop' -ErrorAction SilentlyContinue
  $fsw.EnableRaisingEvents = $false
  $fsw.Dispose()
  try { $mutex.ReleaseMutex() | Out-Null } catch {}
  $mutex.Dispose()
  Log 'watcher stopped'
}

