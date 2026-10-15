param(
    [ValidateSet('all', 'archaon-everchosen', 'tamurkhan-chieftains', 'chaos-equipment', 'hero-capacity-test')]
    [string]$Mod = 'all',
    [string]$Distribution = 'Ubuntu',
    [string]$VanillaDb
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
Push-Location $projectRoot
try {
    $wslArgs = @('-d', $Distribution, '--exec')
    if ($VanillaDb) {
        $nativePath = (Resolve-Path -LiteralPath $VanillaDb).Path
        $linuxPath = & wsl.exe -d $Distribution --exec wslpath -a $nativePath.Replace('\', '/')
        if ($LASTEXITCODE -ne 0) { throw 'Cannot convert the native DB path for WSL.' }
        $wslArgs += @('env', "EVERCHOSEN_VANILLA_DB=$($linuxPath.Trim())")
    }
    & wsl.exe @wslArgs bash tools/wsl/build.sh $Mod
    if ($LASTEXITCODE -ne 0) { throw 'Mod build failed.' }
} finally { Pop-Location }
