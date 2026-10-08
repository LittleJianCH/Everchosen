param(
    [ValidateSet('all', 'archaon-everchosen', 'tamurkhan-chieftains')]
    [string]$Mod = 'all',
    [string]$Distribution = 'Ubuntu'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
Push-Location $projectRoot
try {
    & wsl.exe -d $Distribution -- bash tools/wsl/build.sh $Mod
    if ($LASTEXITCODE -ne 0) { throw 'Mod build failed.' }
} finally { Pop-Location }
