[CmdletBinding(PositionalBinding = $false)]
param(
  [string]$StagingPath = 'C:\app-logos',
  [string]$BasePushScript = "$PSScriptRoot\push-assets.ps1",
  [switch]$ConvertToWebp,
  [int]$WebpQuality = 82,
  [string]$ExportMode = 'suffix',
  [switch]$KeepLocalCopy = $true,
  [string]$KeepDir = 'C:\app-logos\_keep',
  [string]$PipelineLogPath = 'C:\app-logos\logs.txt',
  [string]$UrlsLogPath = 'C:\app-logos\url database.txt',
  [string[]]$ResizeWidths = @('256','512','1024','2048')
)

$ErrorActionPreference = 'Stop'

function Ensure-Folder([string]$Path){ if(-not (Test-Path -LiteralPath $Path)){ New-Item -ItemType Directory -Path $Path -Force | Out-Null } }
function Add-ContentSafe([string]$Path,[string]$Value,[int]$Retries=20,[int]$DelayMs=100){ for($i=0;$i -lt $Retries;$i++){ try{ Add-Content -Path $Path -Value $Value; return $true } catch { Start-Sleep -Milliseconds $DelayMs } }; return $false }
function Log([string]$Message){ Ensure-Folder (Split-Path -Path $PipelineLogPath -Parent); [void](Add-ContentSafe -Path $PipelineLogPath -Value ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message)) }

function Log-Url([string]$FileName,[string]$Url){
  Ensure-Folder (Split-Path -Path $UrlsLogPath -Parent)
  if(Test-Path -LiteralPath $UrlsLogPath){ if(Select-String -Path $UrlsLogPath -SimpleMatch -Pattern ("Raw URL   : " + $Url) -Quiet){ return } }
  if(-not (Test-Path -LiteralPath $UrlsLogPath)){
    [void](Add-ContentSafe -Path $UrlsLogPath -Value 'ASSET URL DATABASE')
    [void](Add-ContentSafe -Path $UrlsLogPath -Value '==================')
    [void](Add-ContentSafe -Path $UrlsLogPath -Value '')
  }
  [void](Add-ContentSafe -Path $UrlsLogPath -Value ("Date      : {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')))
  [void](Add-ContentSafe -Path $UrlsLogPath -Value ("Image File: {0}" -f $FileName))
  [void](Add-ContentSafe -Path $UrlsLogPath -Value ("Raw URL   : {0}" -f $Url))
  [void](Add-ContentSafe -Path $UrlsLogPath -Value '----------------------------------------')
}

function Normalize-Widths([string[]]$Raw){ $list=New-Object System.Collections.Generic.List[int]; foreach($t in $Raw){ if($null -eq $t){continue}; foreach($p in ($t -split '[,\s]+' | ?{$_})){ try{ [int]$w=$p; if($w -gt 0){$list.Add($w)} } catch{} } }; $out=$list.ToArray()|Sort-Object -Unique; if(-not $out -or $out.Count -eq 0){$out=@(256,512,1024,2048)}; return ,$out }
function Normalize-AssetName([string]$Name){
  $n = $Name.ToLower()
  $n = $n -replace '\s+','-'
  $n = $n -replace '[^a-z0-9._-]','-'
  $n = $n -replace '-{2,}','-'
  return $n.Trim('-')
}
function Normalize-AssetFileName([string]$FullPath){
  $dir=Split-Path $FullPath -Parent
  $name=Split-Path $FullPath -Leaf
  $norm=Normalize-AssetName $name
  if($name -eq $norm){ return $FullPath }
  $target=Join-Path $dir $norm
  if(Test-Path -LiteralPath $target){ $base=[IO.Path]::GetFileNameWithoutExtension($norm); $ext=[IO.Path]::GetExtension($norm); $target=Join-Path $dir ("{0}_{1}{2}" -f $base,(Get-Date -Format 'yyyyMMdd_HHmmssfff'),$ext) }
  Rename-Item -LiteralPath $FullPath -NewName (Split-Path $target -Leaf) -Force
  return $target
}
function Export-Path([string]$OriginalFullPath,[int]$Width,[string]$Ext,[string]$StagingRoot){
  $dir = Split-Path $OriginalFullPath -Parent
  $base = [IO.Path]::GetFileNameWithoutExtension($OriginalFullPath)
  $base = Normalize-AssetName $base
  $e = $Ext.ToLower()
  if($ExportMode -eq 'subfolders'){
    $d=Join-Path $dir $Width
    Ensure-Folder $d
    return Join-Path $d ($base+$e)
  }
  return Join-Path $dir ("{0}_w{1}{2}" -f $base,$Width,$e)
}

function Copy-UrlsToClipboard([string[]]$Urls){
  if(-not $Urls -or $Urls.Count -eq 0){ return $false }
  $payload=($Urls -join [Environment]::NewLine)
  try{ Set-Clipboard -Value $payload; return $true } catch {}
  try{ $payload | clip.exe | Out-Null; return $true } catch {}
  return $false
}

function Show-Notification([string]$Title,[string]$Message){
  try{
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    $ni = New-Object System.Windows.Forms.NotifyIcon
    $ni.Icon = [System.Drawing.SystemIcons]::Information
    $ni.BalloonTipTitle = $Title
    $ni.BalloonTipText = $Message
    $ni.Visible = $true
    $ni.ShowBalloonTip(5000)
    Start-Sleep -Milliseconds 1200
    $ni.Dispose()
    return $true
  } catch {
    Log ("notification failed: {0}" -f $_.Exception.Message)
    return $false
  }
}

$ResizeWidthsInt = Normalize-Widths $ResizeWidths
$ExportMode = $ExportMode.ToLower(); if($ExportMode -ne 'suffix' -and $ExportMode -ne 'subfolders'){ $ExportMode='suffix' }
if(-not (Test-Path -LiteralPath $StagingPath)){ throw "StagingPath not found: $StagingPath" }
if(-not (Test-Path -LiteralPath $BasePushScript)){ throw "BasePushScript not found: $BasePushScript" }
if(($ConvertToWebp.IsPresent -or $ResizeWidthsInt.Count -gt 0) -and -not (Get-Command magick -ErrorAction SilentlyContinue)){ throw 'ImageMagick not found (magick.exe).' }

$exts=@('.webp','.png','.jpg','.jpeg','.svg')
$files=Get-ChildItem -LiteralPath $StagingPath -Recurse -File | Where-Object {
  $_.Extension.ToLower() -in $exts -and
  $_.FullName -notlike "$StagingPath\_keep\*" -and
  $_.BaseName -notmatch '_w\d+($|_)' -and
  $_.Name -notin @('logs.txt','url database.txt')
}
if(-not $files){ Log 'Nothing to process.'; return }

Log ("start | files={0} mode={1} widths={2} webp={3}" -f $files.Count,$ExportMode,($ResizeWidthsInt -join ','),$ConvertToWebp)

$files = $files | ForEach-Object { Get-Item -LiteralPath (Normalize-AssetFileName $_.FullName) }

if($KeepLocalCopy){
  foreach($f in $files){
    $relDir = Split-Path ($f.FullName.Substring($StagingPath.Length).TrimStart('\\')) -Parent
    if([string]::IsNullOrWhiteSpace($relDir)){ $keepTargetDir = $KeepDir } else { $keepTargetDir = Join-Path $KeepDir $relDir }
    Ensure-Folder $keepTargetDir
    $dst = Join-Path $keepTargetDir $f.Name
    Copy-Item -LiteralPath $f.FullName -Destination $dst -Force
    Log ("kept local copy: {0}" -f $dst)
  }
}

foreach($f in $files){
  $inExt=$f.Extension.ToLower()
  if($inExt -eq '.svg'){ continue }
  foreach($w in $ResizeWidthsInt){
    if($ConvertToWebp){ $out=Export-Path -OriginalFullPath $f.FullName -Width $w -Ext '.webp' -StagingRoot $StagingPath; & magick $f.FullName -resize ("{0}x" -f $w) -quality $WebpQuality $out 2>&1 | % { Log ("magick: {0}" -f $_.ToString()) } }
    else { $out=Export-Path -OriginalFullPath $f.FullName -Width $w -Ext $inExt -StagingRoot $StagingPath; & magick $f.FullName -resize ("{0}x" -f $w) $out 2>&1 | % { Log ("magick: {0}" -f $_.ToString()) } }
    Log ("variant created: {0}" -f $out)
  }
}

Log ("calling base push script: {0}" -f $BasePushScript)
$oldNativePref = $null
if(Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue){
  $oldNativePref = $PSNativeCommandUseErrorActionPreference
  $PSNativeCommandUseErrorActionPreference = $false
}
$oldEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$baseOutput=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $BasePushScript 2>&1
$ErrorActionPreference = $oldEap
if($null -ne $oldNativePref){ $PSNativeCommandUseErrorActionPreference = $oldNativePref }
foreach($line in $baseOutput){ [void](Add-ContentSafe -Path $PipelineLogPath -Value ($line.ToString())) }

$allUrls=@()
$re='https://raw\.githubusercontent\.com/.+'
foreach($line in $baseOutput){
  foreach($m in [regex]::Matches($line.ToString(),$re)){
    $u = $m.Value.Trim()
    $u = $u -replace ' ','%20'
    $allUrls += $u
  }
}
$allUrls = $allUrls | Sort-Object -Unique
foreach($u in $allUrls){ Log-Url -FileName ([IO.Path]::GetFileName($u)) -Url $u }

$clipOk = Copy-UrlsToClipboard -Urls $allUrls
if($clipOk){ Log ("clipboard copied urls={0}" -f $allUrls.Count) } else { Log 'clipboard copy failed' }
if($allUrls.Count -gt 0){ [void](Show-Notification -Title 'FENIX Asset Pipeline' -Message ("Uploaded {0} URL(s). Clipboard ready." -f $allUrls.Count)) }

Log ("end | urls={0}" -f $allUrls.Count)

