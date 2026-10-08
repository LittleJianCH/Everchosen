param([string]$Distribution = 'Ubuntu')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
Push-Location $projectRoot
try {
    & wsl.exe -d $Distribution -- bash tools/wsl/check.sh
    if ($LASTEXITCODE -ne 0) { throw 'WSL Lua/Fennel toolchain check failed.' }
} finally { Pop-Location }
