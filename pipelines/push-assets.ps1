$ErrorActionPreference = "Stop"

$repo    = "$HOME\fenix-assets"
$staging = "C:\app-logos"

Set-Location $repo

$files = Get-ChildItem $staging -File | Where-Object {
  $_.Extension.ToLower() -in @(".webp",".png",".jpg",".jpeg",".svg")
}

if (!$files) { 
  Write-Host "No assets in staging folder."
  exit 
}

$rawUrls = @()

foreach ($file in $files) {

    # force lowercase filenames for predictable GitHub URLs
    $lowerName = $file.Name.ToLower()
    if ($file.Name -ne $lowerName) {
        Rename-Item -Path $file.FullName -NewName $lowerName -Force
        $file = Get-Item (Join-Path $staging $lowerName)
    }

    $name = $file.Name

    # route by app keyword in filename
    if ($name -like "*kaboozi*") {
        $destRel = "apps/kaboozi/logos/$name"
    }
    elseif ($name -like "*ai-geek-hub*" -or $name -like "*aigeekhub*") {
        $destRel = "apps/ai-geek-hub/logos/$name"
    }
    elseif ($name -like "*sentix*") {
        $destRel = "apps/sentix/logos/$name"
    }
    elseif ($name -like "*havoc*") {
        $destRel = "apps/havoc/logos/$name"
    }
    elseif ($name -like "*profitlinkz*") {
        $destRel = "apps/profitlinkz/logos/$name"
    }
    else {
        $destRel = "shared/logos/$name"
    }

    $destAbs = Join-Path $repo $destRel
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destAbs) | Out-Null

    Move-Item -Path $file.FullName -Destination $destAbs -Force
    Write-Host "Moved -> $destRel"

    $rawUrls += $destRel
}

git add . | Out-Null

# commit only if staged changes exist
git diff --cached --quiet
if ($LASTEXITCODE -eq 0) {
  Write-Host "No changes to commit."
} else {
  git commit -m "auto asset push" | Out-Null
  git push | Out-Null
}

$user = (& gh api user --jq ".login").Trim()
$repoName = "fenix-assets"

Write-Host ""
Write-Host "RAW URLs:"
foreach ($rel in ($rawUrls | Sort-Object -Unique)) {
  Write-Host "https://raw.githubusercontent.com/$user/$repoName/main/$rel"
}
Write-Host ""
