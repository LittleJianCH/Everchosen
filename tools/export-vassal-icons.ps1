#Requires -Version 7.0
# Export UI-specific layouts without changing the full-size faction flags.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$root = Split-Path $PSScriptRoot -Parent

# Scan in compiled code: source art is much larger than the exported UI images.
$drawingAssemblies = @(
    [Drawing.Bitmap].Assembly.Location,
    [Drawing.Rectangle].Assembly.Location
)
Add-Type -ReferencedAssemblies $drawingAssemblies -TypeDefinition @'
using System;
using System.Drawing;
public static class VassalIconBounds {
    public static Rectangle Measure(Bitmap image) {
        int left = image.Width, top = image.Height, right = -1, bottom = -1;
        for (int y = 0; y < image.Height; y++) {
            for (int x = 0; x < image.Width; x++) {
                if (image.GetPixel(x, y).A <= 16) continue;
                left = Math.Min(left, x);
                top = Math.Min(top, y);
                right = Math.Max(right, x);
                bottom = Math.Max(bottom, y);
            }
        }
        if (right < 0) throw new ArgumentException("The source image is empty.");
        return new Rectangle(left, top, right - left + 1, bottom - top + 1);
    }
}
'@

function Get-VisibleBounds([Drawing.Bitmap]$Image) {
    return [VassalIconBounds]::Measure($Image)
}

function New-Graphics([Drawing.Bitmap]$Image) {
    $graphics = [Drawing.Graphics]::FromImage($Image)
    $graphics.InterpolationMode = 'HighQualityBicubic'
    $graphics.PixelOffsetMode = 'HighQuality'
    $graphics.CompositingQuality = 'HighQuality'
    return $graphics
}

function Export-Layout($Source, $Path, $Canvas, $Box, $Angle, $Fit) {
    $image = [Drawing.Bitmap]::new($Source)
    $bounds = Get-VisibleBounds $image
    $side = [int]([Math]::Ceiling(
        [Math]::Sqrt($bounds.Width * $bounds.Width +
            $bounds.Height * $bounds.Height)) + 8)
    $rotated = [Drawing.Bitmap]::new($side, $side)
    $graphics = New-Graphics $rotated
    $graphics.TranslateTransform($side / 2, $side / 2)
    $graphics.RotateTransform($Angle)
    $destination = [Drawing.Rectangle]::new(
        -[int]($bounds.Width / 2), -[int]($bounds.Height / 2),
        $bounds.Width, $bounds.Height)
    $graphics.DrawImage($image, $destination, $bounds, 'Pixel')
    $graphics.Dispose()
    $image.Dispose()
    $bounds = Get-VisibleBounds $rotated
    $width = $Box[2]
    $height = $Box[3]
    if ($Fit) {
        $scale = [Math]::Min($width / $bounds.Width,
            $height / $bounds.Height)
        $width = [int][Math]::Round($bounds.Width * $scale)
        $height = [int][Math]::Round($bounds.Height * $scale)
    }
    $destination = [Drawing.Rectangle]::new(
        $Box[0] + [int](($Box[2] - $width) / 2),
        $Box[1] + [int](($Box[3] - $height) / 2), $width, $height)
    $output = [Drawing.Bitmap]::new($Canvas[0], $Canvas[1])
    $graphics = New-Graphics $output
    $graphics.DrawImage($rotated, $destination, $bounds, 'Pixel')
    $graphics.Dispose()
    $rotated.Dispose()
    $output.Save($Path, [Drawing.Imaging.ImageFormat]::Png)
    $output.Dispose()
}

# WH3 9.0.3 native alpha bounds: Wulfrik, Zhatan, and Khazrak.
# Map flags use the native occupied rectangle and counterclockwise tilt.
# Standalone emblems keep their aspect ratio inside the native icon rectangle.
$layouts = @(
    @{ Race = 'nor'; Name = 'norsca'; Map = @(28, 16, 63, 63)
        Icon = @(14, 13, 229, 229) },
    @{ Race = 'chd'; Name = 'chaos-dwarfs'; Map = @(29, 14, 60, 59)
        Icon = @(46, 41, 166, 153) },
    @{ Race = 'bst'; Name = 'beastmen'; Map = @(29, 15, 61, 62)
        Icon = @(37, 40, 182, 178) }
)
foreach ($layout in $layouts) {
    $source = Join-Path $root "art/vassals/$($layout.Name)-v1.png"
    $emblem = Join-Path $root "art/vassals/$($layout.Name)-emblem.png"
    $output = Join-Path $root (
        'mods/archaon-everchosen/assets/ui/flags/' +
        "everchosen_subjugation_$($layout.Race)_vassal_owner")
    Export-Layout $source (Join-Path $output 'mon_rotated.png') `
        @(112, 90) $layout.Map -10 $false
    Export-Layout $emblem (Join-Path $output 'mon_icon.png') `
        @(256, 256) $layout.Icon 0 $true
}
