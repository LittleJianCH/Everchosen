function ConvertTo-PackResourcePaths {
    param([string[]]$OutputLines)
    # RPFM emits startup logs on stdout alongside the resource paths.
    $OutputLines | Where-Object {
        $_ -and $_ -notmatch '^\d{2}:\d{2}:\d{2} \[[A-Z]+\] '
    }
}

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
