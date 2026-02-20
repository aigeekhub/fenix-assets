[CmdletBinding()]
param(
  [string]$StagingPath = 'C:\app-logos',
  [string]$PushScript = '',
  [string]$BasePushScript = '',
  [string]$LogPath = '',
  [int]$PollSeconds = 8,
  [int]$StableChecks = 5,
  [int]$StableDelayMs = 300
)
$ErrorActionPreference='Stop'
$mutexName='Global\FENIX.AssetPipeline.Watcher'
$createdNew=$false
$mutex=New-Object System.Threading.Mutex($true,$mutexName,[ref]$createdNew)
if(-not $createdNew){ exit 0 }

$scriptDir=Split-Path -Path $MyInvocation.MyCommand.Path -Parent
if([string]::IsNullOrWhiteSpace($PushScript)){ $PushScript=Join-Path $scriptDir 'push-assets.pro.ps1' }
if([string]::IsNullOrWhiteSpace($BasePushScript)){ $BasePushScript=Join-Path $scriptDir 'push-assets.ps1' }
if([string]::IsNullOrWhiteSpace($LogPath)){ $LogPath=Join-Path $scriptDir 'logs\watch-assets.log' }

function Ensure-Folder([string]$Path){ if(-not (Test-Path -LiteralPath $Path)){ New-Item -ItemType Directory -Path $Path -Force | Out-Null } }
function Log([string]$Message){ Ensure-Folder (Split-Path -Path $LogPath -Parent); Add-Content -Path $LogPath -Value ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$Message) }
function Test-FileStable([string]$Path){ $last=-1;$stable=0; for($i=0;$i -lt 80;$i++){ try{ $fi=Get-Item -LiteralPath $Path -ErrorAction Stop; $len=$fi.Length; $fs=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read); $fs.Close(); if($len -eq $last){$stable++}else{$stable=0}; $last=$len; if($stable -ge $StableChecks){return $true} } catch { $stable=0 }; Start-Sleep -Milliseconds $StableDelayMs }; return $false }

Ensure-Folder $StagingPath
Ensure-Folder (Split-Path -Path $LogPath -Parent)
$startedAt = Get-Date

$supported=@('.webp','.png','.jpg','.jpeg','.svg')
$seen = @{}

$existing = Get-ChildItem -LiteralPath $StagingPath -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
  $supported -contains $_.Extension.ToLower() -and
  $_.FullName -notlike "$StagingPath\\_keep\\*" -and
  $_.BaseName -notmatch '_w\d+($|_)' -and
  $_.Name -notin @('logs.txt','url database.txt')
}
foreach($f in $existing){ $seen[$f.FullName] = $f.LastWriteTimeUtc.Ticks }

Log ("watcher start | staging={0} push={1} seeded={2}" -f $StagingPath,$PushScript,$seen.Count)

while($true){
  try{
    $files=Get-ChildItem -LiteralPath $StagingPath -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
      $supported -contains $_.Extension.ToLower() -and
      $_.FullName -notlike "$StagingPath\\_keep\\*" -and
      $_.BaseName -notmatch '_w\d+($|_)' -and
      $_.Name -notin @('logs.txt','url database.txt')
    }

    $newCandidates = @()
    foreach($f in $files){
      $tick = $f.LastWriteTimeUtc.Ticks
      if($seen.ContainsKey($f.FullName)){
        if($seen[$f.FullName] -ne $tick){ $newCandidates += $f }
      } else {
        $newCandidates += $f
      }
    }

    if($newCandidates.Count -gt 0){
      $ready=$false
      foreach($f in $newCandidates){ if(Test-FileStable $f.FullName){ $ready=$true; break } }
      if($ready){
        Log ("detected {0} NEW file(s) | running pipeline" -f $newCandidates.Count)
        $out=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $PushScript -ConvertToWebp -WebpQuality 82 -StagingPath $StagingPath -BasePushScript $BasePushScript -ResizeWidths '256,512,1024,2048' 2>&1
        foreach($line in $out){ Add-Content -Path $LogPath -Value ($line.ToString()) }
        Start-Sleep -Seconds 2
      }
    }

    $seen = @{}
    foreach($f in $files){ $seen[$f.FullName] = $f.LastWriteTimeUtc.Ticks }

  } catch { Log ("ERROR: {0}" -f $_.Exception.Message) }
  Start-Sleep -Seconds $PollSeconds
}

