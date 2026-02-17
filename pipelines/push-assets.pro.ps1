# push-assets.pro.ps1 (Windows PowerShell 5.1 compatible)
# Pro wrapper:
# - Forces lowercase filenames in staging (C:\app-logos)
# - Keeps a local copy under C:\app-logos\_keep\
# - Optional variants (resize + webp) using ImageMagick
# - Calls existing push-assets.ps1 (routing + git add/commit/push + prints raw URLs)
# - Logs everything to pipeline.log
# - Logs URLs to urls.log
#
# ResizeWidths supports:
#   -ResizeWidths 256 512 1024 2048   (SPACE separated)
#   -ResizeWidths "256,512,1024,2048" (SINGLE token)
#
# CRITICAL: ResizeWidths is last and uses ValueFromRemainingArguments so PS 5.1 binds it correctly.

[CmdletBinding()]
param(
  [string]$StagingPath = "C:\app-logos",
  [string]$BasePushScript = "$PSScriptRoot\push-assets.ps1",

  [switch]$ConvertToWebp,
  [int]$WebpQuality = 82,

  # naming (kept as string to avoid pre-run binding crashes)
  [string]$ExportMode = "suffix",  # suffix or subfolders

  [switch]$KeepLocalCopy = $true,
  [string]$KeepDir = "C:\app-logos\_keep",

  [string]$PipelineLogPath = "$env:USERPROFILE\fenix-assets\pipelines\logs\pipeline.log",
  [string]$UrlsLogPath     = "$env:USERPROFILE\fenix-assets\pipelines\logs\urls.log",

  # MUST BE LAST
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$ResizeWidths = @("256","512","1024","2048")
)

$ErrorActionPreference = "Stop"

function Ensure-Folder([string]$p) {
  if (-not (Test-Path -LiteralPath $p)) {
    New-Item -ItemType Directory -Force -Path $p | Out-Null
  }
}

function Log([string]$msg) {
  Ensure-Folder (Split-Path $PipelineLogPath -Parent)
  $stamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  Add-Content -Path $PipelineLogPath -Value "[$stamp] $msg"
}

function Log-Url([string]$fileName, [string]$url) {
  Ensure-Folder (Split-Path $UrlsLogPath -Parent)
  $stamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  Add-Content -Path $UrlsLogPath -Value "[$stamp] $fileName`t$url"
}

function To-LowercaseFileName([string]$fullPath) {
  $dir   = Split-Path $fullPath -Parent
  $name  = Split-Path $fullPath -Leaf
  $lower = $name.ToLower()

  if ($name -eq $lower) { return $fullPath }

  $target = Join-Path $dir $lower

  if (Test-Path -LiteralPath $target) {
    $base = [System.IO.Path]::GetFileNameWithoutExtension($lower)
    $ext  = [System.IO.Path]::GetExtension($lower)
    $ts   = (Get-Date).ToString("yyyyMMdd_HHmmssfff")
    $target = Join-Path $dir ("{0}_{1}{2}" -f $base, $ts, $ext)
  }

  Rename-Item -LiteralPath $fullPath -NewName (Split-Path $target -Leaf) -Force
  return $target
}

# Normalize ExportMode safely
if ($null -eq $ExportMode) { $ExportMode = "suffix" }
$ExportMode = $ExportMode.ToString().ToLower().Trim()
if ($ExportMode -ne "suffix" -and $ExportMode -ne "subfolders") { $ExportMode = "suffix" }

function Export-Path([string]$baseName, [int]$w, [string]$ext) {
  $baseName = $baseName.ToLower()
  $ext = $ext.ToLower()

  if ($ExportMode -eq "subfolders") {
    $dir = Join-Path $StagingPath $w
    Ensure-Folder $dir
    return Join-Path $dir ($baseName + $ext)
  }

  return Join-Path $StagingPath ("{0}_w{1}{2}" -f $baseName, $w, $ext)
}

function Normalize-ResizeWidths([string[]]$items) {
  $list = New-Object System.Collections.Generic.List[int]

  foreach ($item in $items) {
    if ($null -eq $item) { continue }

    # supports both: 256 512 1024 2048 and "256,512,1024,2048"
    $parts = $item -split '[,\s]+' | Where-Object { $_ -and $_.Trim() -ne "" }
    foreach ($p in $parts) {
      try {
        [int]$w = $p
        if ($w -gt 0) { $list.Add($w) }
      } catch { }
    }
  }

  $out = $list.ToArray() | Sort-Object -Unique
  if (-not $out -or $out.Count -eq 0) { $out = @(256,512,1024,2048) }
  return ,$out
}

$ResizeWidthsInt = Normalize-ResizeWidths $ResizeWidths

if (-not (Test-Path -LiteralPath $StagingPath)) {
  throw "StagingPath not found: $StagingPath"
}
if (-not (Test-Path -LiteralPath $BasePushScript)) {
  throw "BasePushScript not found: $BasePushScript"
}

$exts = @(".webp",".png",".jpg",".jpeg",".svg")

# Only staging root. Avoid loops.
$files = Get-ChildItem -LiteralPath $StagingPath -File | Where-Object {
  $_.Extension.ToLower() -in $exts
}

if (-not $files) { return }

# ImageMagick required for raster processing
$needsMagick = $ConvertToWebp.IsPresent -or ($ResizeWidthsInt.Count -gt 0)
if ($needsMagick) {
  $magick = Get-Command magick -ErrorAction SilentlyContinue
  if (-not $magick) {
    throw "ImageMagick not found. Install with: winget install -e --id ImageMagick.ImageMagick"
  }
}

Log "PRO push start. Found=$($files.Count) ConvertToWebp=$ConvertToWebp ExportMode=$ExportMode ResizeWidths=$($ResizeWidthsInt -join ',') KeepLocalCopy=$KeepLocalCopy"

# 1) Force lowercase names
$loweredPaths = @()
foreach ($f in $files) {
  $loweredPaths += (To-LowercaseFileName $f.FullName)
}

$files = $loweredPaths | ForEach-Object { Get-Item -LiteralPath $_ }

# 2) Keep local copies
if ($KeepLocalCopy) {
  Ensure-Folder $KeepDir
  foreach ($f in $files) {
    $dest = Join-Path $KeepDir (Split-Path $f.FullName -Leaf)
    Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
    Log "Kept local copy: $dest"
  }
}

# 3) Variants (skip svg)
foreach ($f in $files) {
  $inPath   = $f.FullName
  $inExt    = $f.Extension.ToLower()
  $baseName = [System.IO.Path]::GetFileNameWithoutExtension($f.Name).ToLower()

  if ($inExt -eq ".svg") { continue }

  foreach ($w in $ResizeWidthsInt) {
    if ($w -le 0) { continue }

    if ($ConvertToWebp) {
      $out = Export-Path $baseName $w ".webp"
      & magick $inPath -resize "$w"x -quality $WebpQuality $out
      Log "Variant created: $out"
    } else {
      $out = Export-Path $baseName $w $inExt
      & magick $inPath -resize "$w"x $out
      Log "Variant created: $out"
    }
  }
}

# 4) Call base push script
Log "Calling base push script: $BasePushScript"
$baseOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $BasePushScript 2>&1

foreach ($line in $baseOutput) {
  Add-Content -Path $PipelineLogPath -Value $line
}

# 5) Extract raw URLs
$rawUrlRegex = 'https://raw\.githubusercontent\.com/[^\s"]+'
$allUrls = @()

foreach ($line in $baseOutput) {
  $matches = [regex]::Matches($line, $rawUrlRegex)
  foreach ($m in $matches) { $allUrls += $m.Value }
}

foreach ($u in $allUrls) {
  $fileName = [System.IO.Path]::GetFileName($u)
  Log-Url $fileName $u
}

Log "Base push complete. URLsLogged=$($allUrls.Count)"
Log "PRO push end."
