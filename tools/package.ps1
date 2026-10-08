#Requires -Version 7.0
param(
    [ValidateSet('all', 'archaon-everchosen', 'tamurkhan-chieftains', 'chaos-equipment')]
    [string]$Mod = 'all',
    [string]$Rpfm = $env:RPFM_CLI,
    [string]$Schema = $env:WH3_SCHEMA,
    [string]$GameData = $env:WH3_DATA,
    [string]$Distribution = 'Ubuntu'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
if (-not $Rpfm -or -not $Schema) {
    throw 'Supply -Rpfm and -Schema, or set RPFM_CLI and WH3_SCHEMA.'
}
$Rpfm = (Resolve-Path -LiteralPath $Rpfm).Path
$Schema = (Resolve-Path -LiteralPath $Schema).Path
$mods = if ($Mod -eq 'all') { @('archaon-everchosen', 'tamurkhan-chieftains', 'chaos-equipment') } else { @($Mod) }
$localRoot = [System.IO.Path]::GetFullPath((Join-Path $projectRoot '.local'))
$work = Join-Path $localRoot ('package-' + [guid]::NewGuid().ToString('N'))
[System.IO.Directory]::CreateDirectory($work) | Out-Null

function Invoke-Rpfm([string[]]$Arguments) {
    & $Rpfm -g warhammer_3 @Arguments
    if ($LASTEXITCODE -ne 0) { throw "RPFM failed: $($Arguments[0..1] -join ' ')" }
}

try {
    $native = $null
    if ($mods -contains 'chaos-equipment') {
        if (-not $GameData) { throw 'Equipment packaging requires -GameData or WH3_DATA.' }
        $gamePack = (Resolve-Path -LiteralPath (Join-Path $GameData 'db.pack')).Path
        $native = Join-Path $work 'vanilla'
        $extract = @('pack', 'extract', '-p', $gamePack, '-t', $Schema)
        foreach ($table in @('ancillaries', 'faction_sets', 'faction_set_items', 'factions', 'cultures')) {
            $extract += @('-F', "db/$($table)_tables;$native")
        }
        Invoke-Rpfm $extract
    }

    & (Join-Path $PSScriptRoot 'build.ps1') -Mod $Mod -Distribution $Distribution -VanillaDb $native
    $dist = Join-Path $projectRoot 'dist'
    [System.IO.Directory]::CreateDirectory($dist) | Out-Null
    foreach ($item in $mods) {
        $source = Join-Path $projectRoot "build/$item"
        $name = 'everchosen_' + $item.Replace('-', '_') + '.pack'
        $pack = Join-Path $work $name
        Invoke-Rpfm @('pack', 'create', '-p', $pack)
        Invoke-Rpfm @('pack', 'add', '-p', $pack, '-t', $Schema, '-F', "$source;/")

        $packPaths = @(Invoke-Rpfm @('pack', 'list', '-p', $pack))
        # Confirm DB encoding and source preservation before replacing a deliverable.
        $decoded = Join-Path $work "$item-roundtrip"
        Invoke-Rpfm @('pack', 'extract', '-p', $pack, '-t', $Schema, '-F', "/;$decoded")
        foreach ($file in Get-ChildItem -LiteralPath $source -File -Recurse) {
            $relative = [System.IO.Path]::GetRelativePath($source, $file.FullName)
            $actual = Join-Path $decoded $relative
            if (-not (Test-Path -LiteralPath $actual -PathType Leaf)) {
                throw "Pack round-trip missing: $relative"
            }
            if ($file.Extension -eq '.tsv') {
                $internalPath = $relative.Replace('\', '/')
                $encodedPath = $internalPath -replace '\.tsv$', ''
                if ($packPaths -cnotcontains $encodedPath -or $packPaths -ccontains $internalPath) {
                    throw "Table was not encoded to an internal DB/Loc resource: $relative"
                }
                $before = [System.IO.File]::ReadAllLines($file.FullName)
                $after = [System.IO.File]::ReadAllLines($actual)
                if ($before.Length -lt 3 -or $after.Length -lt 3 -or $before[0] -cne $after[0] -or
                    (($before[1] -split ';')[0..1] -join ';') -cne (($after[1] -split ';')[0..1] -join ';') -or
                    (Compare-Object -CaseSensitive ($before | Select-Object -Skip 2) ($after | Select-Object -Skip 2))) {
                    throw "Pack round-trip changed DB rows/schema: $relative"
                }
                $binaryPath = Join-Path $decoded ($relative -replace '\.tsv$', '')
                if (Test-Path -LiteralPath $binaryPath) { throw "Undecoded DB resource: $relative" }
            } elseif ((Get-FileHash -LiteralPath $file.FullName).Hash -ne (Get-FileHash -LiteralPath $actual).Hash) {
                throw "Pack round-trip changed asset: $relative"
            }
        }
        $destination = Join-Path $dist $name
        Move-Item -LiteralPath $pack -Destination $destination -Force
        Get-FileHash -LiteralPath $destination -Algorithm SHA256
    }
} finally {
    # The disposable extraction directory must resolve inside this repository's .local.
    $resolvedWork = [System.IO.Path]::GetFullPath($work)
    if (-not $resolvedWork.StartsWith($localRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Refusing to clean a path outside the local build directory.'
    }
    if (Test-Path -LiteralPath $resolvedWork) { Remove-Item -LiteralPath $resolvedWork -Recurse -Force }
}
