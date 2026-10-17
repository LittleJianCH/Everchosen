function Assert-PackResourcePreservation {
    param(
        [string[]]$PreviousPaths,
        [string[]]$NewPaths,
        [switch]$AllowResourceRemoval
    )
    $removed = @($PreviousPaths | Where-Object { $_ -cnotin $NewPaths })
    if ($removed.Count -and -not $AllowResourceRemoval) {
        $examples = ($removed | Select-Object -First 10) -join "`n"
        throw "Refusing to replace a pack with $($removed.Count) removed resource paths:`n$examples`nIntegrate the missing source, or review an intentional removal before using -AllowResourceRemoval."
    }
}
