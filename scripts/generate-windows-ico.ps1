param(
    [Parameter(Mandatory = $true)]
    [string]$SourcePng,

    [Parameter(Mandatory = $true)]
    [string]$DestinationIco
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing

# Include standard shell/taskbar sizes to avoid generic icon fallbacks.
$sizes = @(16, 24, 32, 48, 64, 128, 256)

$source = [System.Drawing.Image]::FromFile($SourcePng)
$pngFrames = New-Object System.Collections.Generic.List[byte[]]

try {
    foreach ($size in $sizes) {
        $bitmap = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        try {
            $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
            try {
                $graphics.Clear([System.Drawing.Color]::Transparent)
                $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
                $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
                $graphics.DrawImage($source, 0, 0, $size, $size)

                $ms = New-Object System.IO.MemoryStream
                try {
                    $bitmap.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
                    $pngFrames.Add($ms.ToArray())
                } finally {
                    $ms.Dispose()
                }
            } finally {
                $graphics.Dispose()
            }
        } finally {
            $bitmap.Dispose()
        }
    }
} finally {
    $source.Dispose()
}

$destinationDir = Split-Path -Parent $DestinationIco
if (-not [string]::IsNullOrWhiteSpace($destinationDir) -and -not (Test-Path -LiteralPath $destinationDir)) {
    New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
}

$file = [System.IO.File]::Open($DestinationIco, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
$writer = New-Object System.IO.BinaryWriter($file)

try {
    # ICONDIR header
    $writer.Write([UInt16]0) # reserved
    $writer.Write([UInt16]1) # type: ICO
    $writer.Write([UInt16]$pngFrames.Count)

    $imageOffset = 6 + ($pngFrames.Count * 16)

    for ($i = 0; $i -lt $pngFrames.Count; $i++) {
        $size = $sizes[$i]
        $png = $pngFrames[$i]

        # ICONDIRENTRY
        $writer.Write([byte]($(if ($size -ge 256) { 0 } else { $size })))
        $writer.Write([byte]($(if ($size -ge 256) { 0 } else { $size })))
        $writer.Write([byte]0)       # color count
        $writer.Write([byte]0)       # reserved
        $writer.Write([UInt16]1)     # planes
        $writer.Write([UInt16]32)    # bit count
        $writer.Write([UInt32]$png.Length)
        $writer.Write([UInt32]$imageOffset)

        $imageOffset += $png.Length
    }

    foreach ($png in $pngFrames) {
        $writer.Write($png)
    }
} finally {
    $writer.Dispose()
    $file.Dispose()
}

Write-Host "Generated ICO: $DestinationIco"
