$ErrorActionPreference = "Stop"

$repo    = "$HOME\fenix-assets"
$staging = "C:\app-logos"

Set-Location $repo

$supported = @(".webp", ".png", ".jpg", ".jpeg", ".svg")
$files = Get-ChildItem -LiteralPath $staging -Recurse -File | Where-Object {
  $_.Extension.ToLower() -in $supported -and
  $_.FullName -notlike "C:\app-logos\_keep\*" -and
  $_.Name -notin @("logs.txt","url database.txt")
}

if (-not $files) {
  Write-Host "No assets in staging folder."
  exit
}

function Normalize-AssetName([string]$Name){
  $n = $Name.ToLower()
  $n = $n -replace '\s+','-'
  $n = $n -replace '[^a-z0-9._-]','-'
  $n = $n -replace '-{2,}','-'
  return $n.Trim('-')
}

$rawUrls = @()

foreach ($file in $files) {
  $norm = Normalize-AssetName $file.Name
  $current = $file
  if ($file.Name -ne $norm) {
    Rename-Item -LiteralPath $file.FullName -NewName $norm -Force
    $current = Get-Item -LiteralPath (Join-Path $file.DirectoryName $norm)
  }

  $rel = $current.FullName.Substring($staging.Length).TrimStart('\\')
  $destRel = ($rel -replace '\\','/')
  $destAbs = Join-Path $repo $rel

  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destAbs) | Out-Null
  Move-Item -LiteralPath $current.FullName -Destination $destAbs -Force
  Write-Host "Moved -> $destRel"
  $rawUrls += $destRel
}

git add . | Out-Null
git diff --cached --quiet
if ($LASTEXITCODE -ne 0) {
  git commit -m "auto asset push" | Out-Null
  git push | Out-Null
} else {
  Write-Host "No changes to commit."
}

$user = (& gh api user --jq ".login").Trim()
$repoName = "fenix-assets"

Write-Host ""
Write-Host "RAW URLs:"
foreach ($rel in ($rawUrls | Sort-Object -Unique)) {
  $urlRel = $rel -replace ' ','%20'
  Write-Host "https://raw.githubusercontent.com/$user/$repoName/main/$urlRel"
}
Write-Host ""
