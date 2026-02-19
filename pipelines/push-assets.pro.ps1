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
function To-LowercaseFileName([string]$FullPath){ $dir=Split-Path $FullPath -Parent; $name=Split-Path $FullPath -Leaf; $low=$name.ToLower(); if($name -eq $low){ return $FullPath }; $target=Join-Path $dir $low; if(Test-Path -LiteralPath $target){ $base=[IO.Path]::GetFileNameWithoutExtension($low); $ext=[IO.Path]::GetExtension($low); $target=Join-Path $dir ("{0}_{1}{2}" -f $base,(Get-Date -Format 'yyyyMMdd_HHmmssfff'),$ext) }; Rename-Item -LiteralPath $FullPath -NewName (Split-Path $target -Leaf) -Force; return $target }
function Export-Path([string]$BaseName,[int]$Width,[string]$Ext){ $b=$BaseName.ToLower(); $e=$Ext.ToLower(); if($ExportMode -eq 'subfolders'){ $d=Join-Path $StagingPath $Width; Ensure-Folder $d; return Join-Path $d ($b+$e) }; return Join-Path $StagingPath ("{0}_w{1}{2}" -f $b,$Width,$e) }

function Copy-UrlsToClipboard([string[]]$Urls){ if(-not $Urls -or $Urls.Count -eq 0){ return }; $payload=($Urls -join [Environment]::NewLine); try{ Set-Clipboard -Value $payload; return } catch { try{ $payload | clip.exe | Out-Null; return } catch { Log ("clipboard copy failed: {0}" -f $_.Exception.Message) } } }
function Notify-User([string]$Message){ if([string]::IsNullOrWhiteSpace($Message)){ return }; try{ msg.exe $env:USERNAME /time:5 $Message | Out-Null } catch { Log ("notification failed: {0}" -f $_.Exception.Message) } }

$ResizeWidthsInt = Normalize-Widths $ResizeWidths
$ExportMode = $ExportMode.ToLower(); if($ExportMode -ne 'suffix' -and $ExportMode -ne 'subfolders'){ $ExportMode='suffix' }
if(-not (Test-Path -LiteralPath $StagingPath)){ throw "StagingPath not found: $StagingPath" }
if(-not (Test-Path -LiteralPath $BasePushScript)){ throw "BasePushScript not found: $BasePushScript" }
if(($ConvertToWebp.IsPresent -or $ResizeWidthsInt.Count -gt 0) -and -not (Get-Command magick -ErrorAction SilentlyContinue)){ throw 'ImageMagick not found (magick.exe).' }

$exts=@('.webp','.png','.jpg','.jpeg','.svg')
$files=Get-ChildItem -LiteralPath $StagingPath -File | Where-Object {
  $_.Extension.ToLower() -in $exts -and
  $_.BaseName -notmatch '_w\d+($|_)' -and
  $_.Name -notin @('logs.txt','url database.txt')
}
if(-not $files){ Log 'Nothing to process.'; return }

Log ("start | files={0} mode={1} widths={2} webp={3}" -f $files.Count,$ExportMode,($ResizeWidthsInt -join ','),$ConvertToWebp)

$files = $files | ForEach-Object { Get-Item -LiteralPath (To-LowercaseFileName $_.FullName) }

if($KeepLocalCopy){ Ensure-Folder $KeepDir; foreach($f in $files){ Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $KeepDir $f.Name) -Force; Log ("kept local copy: {0}" -f (Join-Path $KeepDir $f.Name)) } }

foreach($f in $files){
  $inExt=$f.Extension.ToLower()
  if($inExt -eq '.svg'){ continue }
  $base=[IO.Path]::GetFileNameWithoutExtension($f.Name).ToLower()
  foreach($w in $ResizeWidthsInt){
    if($ConvertToWebp){ $out=Export-Path $base $w '.webp'; & magick $f.FullName -resize ("{0}x" -f $w) -quality $WebpQuality $out 2>&1 | % { Log ("magick: {0}" -f $_.ToString()) } }
    else { $out=Export-Path $base $w $inExt; & magick $f.FullName -resize ("{0}x" -f $w) $out 2>&1 | % { Log ("magick: {0}" -f $_.ToString()) } }
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
$re='https://raw\.githubusercontent\.com/[^\s"]+'
foreach($line in $baseOutput){ foreach($m in [regex]::Matches($line.ToString(),$re)){ $allUrls += $m.Value } }
$allUrls = $allUrls | Sort-Object -Unique
foreach($u in $allUrls){ Log-Url -FileName ([IO.Path]::GetFileName($u)) -Url $u }

Copy-UrlsToClipboard -Urls $allUrls
if($allUrls.Count -gt 0){ Notify-User -Message ("Asset pipeline complete. Copied {0} URL(s) to clipboard." -f $allUrls.Count) }

Log ("end | urls={0}" -f $allUrls.Count)
