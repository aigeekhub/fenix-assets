$ErrorActionPreference = "Stop"

$repo = "$HOME\fenix-assets"
$staging = "C:\app-logos"

Set-Location $repo

$files = Get-ChildItem $staging -File
if (!$files) { exit }

foreach ($file in $files) {

    $name = $file.Name.ToLower()

    if ($name -like "*kaboozi*") {
        $dest = "apps/kaboozi/logos/$name"
    }
    elseif ($name -like "*sentix*") {
        $dest = "apps/sentix/logos/$name"
    }
    elseif ($name -like "*havoc*") {
        $dest = "apps/havoc/logos/$name"
    }
    elseif ($name -like "*profitlinkz*") {
        $dest = "apps/profitlinkz/logos/$name"
    }
    else {
        $dest = "shared/logos/$name"
    }

    $fullDest = Join-Path $repo $dest
    Move-Item $file.FullName $fullDest -Force

    Write-Host "Moved → $dest"
}

git add .
git commit -m "auto asset push"
git push

$user = (& gh api user --jq ".login")
Write-Host ""
Write-Host "RAW URL:"
Write-Host "https://raw.githubusercontent.com/$user/fenix-assets/main/$dest"
Write-Host ""
