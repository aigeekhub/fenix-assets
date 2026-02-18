# push-assets.pro.ps1 (FINAL, Windows PowerShell 5.1)
[CmdletBinding(PositionalBinding = $false)]
param(
  [string]$StagingPath = "C:\app-logos",
  [string]$BasePushScript = "$PSScriptRoot\push-assets.ps1",
  [switch]$ConvertToWebp,
  [int]$WebpQuality = 82,
  [string]$ExportMode = "suffix", # suffix | subfolders
  [switch]$KeepLocalCopy = $true,
  [string]$KeepDir = "C:\app-logos\_keep",
  [string]$PipelineLogPath = "C:\app-logos\logs.txt",
  [string]$UrlsLogPath = "C:\app-logos\url database.txt",

  # keep last: allows -ResizeWidths 256 512 1024 2048 OR "256,512,1024,2048"
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$ResizeWidths = @("256","512","1024","2048")
)

$ErrorActionPreference = "Stop"

function Ensure-Folder([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
}

function Log([string]$Message) {
  Ensure-Folder (Split-Path -Path $PipelineLogPath -Parent)
  Add-Content -Path $PipelineLogPath -Value ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message)
}

function Log-Url([string]$FileName, [string]$Url) {
  Ensure-Folder (Split-Path -Path $UrlsLogPath -Parent)

  if (Test-Path -LiteralPath $UrlsLogPath) {
    $already = Select-String -Path $UrlsLogPath -SimpleMatch -Pattern ("Raw URL   : " + $Url) -Quiet
    if ($already) { return }
  }

  if (-not (Test-Path -LiteralPath $UrlsLogPath)) {
    Add-Content -Path $UrlsLogPath -Value "ASSET URL DATABASE"
    Add-Content -Path $UrlsLogPath -Value "=================="
    Add-Content -Path $UrlsLogPath -Value ""
  }

  Add-Content -Path $UrlsLogPath -Value ("Date      : {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
  Add-Content -Path $UrlsLogPath -Value ("Image File: {0}" -f $FileName)
  Add-Content -Path $UrlsLogPath -Value ("Raw URL   : {0}" -f $Url)
  Add-Content -Path $UrlsLogPath -Value "----------------------------------------"
}
function Copy-UrlsToClipboard([string[]]$Urls) {
  if (-not $Urls -or $Urls.Count -eq 0) { return }
  $payload = ($Urls -join [Environment]::NewLine)
  try {
    Set-Clipboard -Value $payload
    return
  } catch {
    try {
      $payload | clip.exe
      return
    } catch {
      Log ("clipboard copy failed: {0}" -f $_.Exception.Message)
    }
  }
}

function Notify-User([string]$Message) {
  if ([string]::IsNullOrWhiteSpace($Message)) { return }

  # Lightweight popup in user session; non-fatal if unavailable.
  try {
    msg.exe $env:USERNAME /time:5 $Message | Out-Null
  } catch {
    Log ("notification failed: {0}" -f $_.Exception.Message)
  }
}


function Normalize-Widths([string[]]$Raw) {
  $list = New-Object System.Collections.Generic.List[int]
  foreach ($token in $Raw) {
    if ($null -eq $token) { continue }
    $parts = ($token -split '[,\s]+' | Where-Object { $_ -and $_.Trim() -ne "" })
    foreach ($p in $parts) {
      try {
        [int]$w = $p
        if ($w -gt 0) { $list.Add($w) }
      } catch {}
    }
  }
  $out = $list.ToArray() | Sort-Object -Unique
  if (-not $out -or $out.Count -eq 0) { $out = @(256,512,1024,2048) }
  return ,$out
}

function To-LowercaseFileName([string]$FullPath) {
  $dir = Split-Path -Path $FullPath -Parent
  $name = Split-Path -Path $FullPath -Leaf
  $lower = $name.ToLower()

  if ($name -eq $lower) { return $FullPath }

  $target = Join-Path -Path $dir -ChildPath $lower
  if (Test-Path -LiteralPath $target) {
    $base = [System.IO.Path]::GetFileNameWithoutExtension($lower)
    $ext = [System.IO.Path]::GetExtension($lower)
    $ts = (Get-Date -Format 'yyyyMMdd_HHmmssfff')
    $target = Join-Path -Path $dir -ChildPath ("{0}_{1}{2}" -f $base, $ts, $ext)
  }

  Rename-Item -LiteralPath $FullPath -NewName (Split-Path -Path $target -Leaf) -Force
  return $target
}

function Export-Path([string]$BaseName, [int]$Width, [string]$Ext) {
  $baseName = $BaseName.ToLower()
  $ext = $Ext.ToLower()

  if ($ExportMode -eq "subfolders") {
    $dir = Join-Path -Path $StagingPath -ChildPath $Width
    Ensure-Folder $dir
    return (Join-Path -Path $dir -ChildPath ($baseName + $ext))
  }

  return (Join-Path -Path $StagingPath -ChildPath ("{0}_w{1}{2}" -f $baseName, $Width, $ext))
}

function Invoke-MagickResize([string]$InputPath, [string]$OutputPath, [int]$Width, [int]$Quality, [switch]$ToWebp) {
  $args = @($InputPath, "-resize", ("{0}x" -f $Width))
  if ($ToWebp) { $args += @("-quality", "$Quality") }
  $args += $OutputPath

  & magick @args 2>&1 | ForEach-Object { Log ("magick: {0}" -f $_.ToString()) }
  if ($LASTEXITCODE -ne 0) {
    throw ("ImageMagick failed for input: {0}" -f $InputPath)
  }
}

# sanitize
$ExportMode = ($ExportMode.ToString().ToLower().Trim())
if ($ExportMode -ne "suffix" -and $ExportMode -ne "subfolders") { $ExportMode = "suffix" }
$ResizeWidthsInt = Normalize-Widths $ResizeWidths

# checks
if (-not (Test-Path -LiteralPath $StagingPath)) { throw "StagingPath not found: $StagingPath" }
if (-not (Test-Path -LiteralPath $BasePushScript)) { throw "BasePushScript not found: $BasePushScript" }

$needsMagick = $ConvertToWebp.IsPresent -or ($ResizeWidthsInt.Count -gt 0)
if ($needsMagick -and -not (Get-Command magick -ErrorAction SilentlyContinue)) {
  throw "ImageMagick (magick.exe) not found. Install: winget install -e --id ImageMagick.ImageMagick"
}

$exts = @(".webp",".png",".jpg",".jpeg",".svg")
$files = Get-ChildItem -LiteralPath $StagingPath -File | Where-Object { $_.Extension.ToLower() -in $exts }
if (-not $files) { Log "Nothing to process."; return }

Log ("start | files={0} mode={1} widths={2} webp={3}" -f $files.Count, $ExportMode, ($ResizeWidthsInt -join ","), $ConvertToWebp)

# lowercase
$lowered = @()
foreach ($f in $files) { $lowered += (To-LowercaseFileName $f.FullName) }
$files = $lowered | ForEach-Object { Get-Item -LiteralPath $_ }

# keep local copy
if ($KeepLocalCopy) {
  Ensure-Folder $KeepDir
  foreach ($f in $files) {
    $dest = Join-Path -Path $KeepDir -ChildPath $f.Name
    Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
    Log ("kept local copy: {0}" -f $dest)
  }
}

# variants
foreach ($f in $files) {
  $inExt = $f.Extension.ToLower()
  if ($inExt -eq ".svg") { continue }

  $base = [System.IO.Path]::GetFileNameWithoutExtension($f.Name).ToLower()

  foreach ($w in $ResizeWidthsInt) {
    if ($w -le 0) { continue }

    if ($ConvertToWebp) {
      $out = Export-Path -BaseName $base -Width $w -Ext ".webp"
      Invoke-MagickResize -InputPath $f.FullName -OutputPath $out -Width $w -Quality $WebpQuality -ToWebp
      Log ("variant created: {0}" -f $out)
    } else {
      $out = Export-Path -BaseName $base -Width $w -Ext $inExt
      Invoke-MagickResize -InputPath $f.FullName -OutputPath $out -Width $w -Quality $WebpQuality
      Log ("variant created: {0}" -f $out)
    }
  }
}

# run base push script
Log ("calling base push script: {0}" -f $BasePushScript)
$prevEap = $ErrorActionPreference
$ErrorActionPreference = "Continue"
$baseOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $BasePushScript 2>&1
$baseExitCode = $LASTEXITCODE
$ErrorActionPreference = $prevEap
foreach ($line in $baseOutput) {
  Add-Content -Path $PipelineLogPath -Value ($line.ToString())
}
if ($baseExitCode -ne 0) {
  Log ("base push exited with code {0}" -f $baseExitCode)
}

# URL extraction
$rawUrlRegex = 'https://raw\.githubusercontent\.com/.+'
$allUrls = @()
foreach ($line in $baseOutput) {
  $matches = [regex]::Matches($line.ToString(), $rawUrlRegex)
  foreach ($m in $matches) { $allUrls += $m.Value }
}
$allUrls = $allUrls | Sort-Object -Unique

foreach ($u in $allUrls) {
  Log-Url -FileName ([System.IO.Path]::GetFileName($u)) -Url $u
}

Log ("end | urls={0}" -f $allUrls.Count)






