$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../../tools/pack-resources.ps1')

$existing = @('script/campaign/mod/everchosen_archaon.lua',
              'ui/everchosen/hero_families.twui.xml')
Assert-PackResourcePreservation -PreviousPaths $existing -NewPaths @(
    $existing + 'text/everchosen_portal_heroes.loc')

$rejected = $false
try {
    Assert-PackResourcePreservation -PreviousPaths $existing -NewPaths @(
        'script/campaign/mod/everchosen_archaon.lua')
} catch {
    if ($_.Exception.Message -notlike '*ui/everchosen/hero_families.twui.xml*') {
        throw
    }
    $rejected = $true
}
if (-not $rejected) { throw 'Missing hero navigation was not rejected.' }

Assert-PackResourcePreservation -PreviousPaths $existing -NewPaths @(
    'script/campaign/mod/everchosen_archaon.lua') -AllowResourceRemoval
Write-Output 'Pack resource checks passed: additions, missing navigation, intentional removal.'
