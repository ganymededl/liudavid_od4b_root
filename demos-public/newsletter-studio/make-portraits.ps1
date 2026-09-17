$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$assets = Join-Path $PSScriptRoot 'assets'
New-Item -ItemType Directory -Force -Path $assets | Out-Null
$portraits = @(
    @{ Background = '#E8DEF3'; Halo = '#D3C1E9'; Skin = '#C98A68'; Hair = '#31273D'; Shirt = '#65509A'; Style = 0 },
    @{ Background = '#DBEEF7'; Halo = '#BFDBED'; Skin = '#754936'; Hair = '#252431'; Shirt = '#246589'; Style = 1 },
    @{ Background = '#F9EAD1'; Halo = '#EED2A7'; Skin = '#E6B28A'; Hair = '#694332'; Shirt = '#9B6539'; Style = 2 },
    @{ Background = '#DFEEE7'; Halo = '#BEDACD'; Skin = '#B77855'; Hair = '#262C32'; Shirt = '#357765'; Style = 3 }
)
for ($index = 0; $index -lt $portraits.Count; $index++) {
    $person = $portraits[$index]
    $bitmap = [System.Drawing.Bitmap]::new(320, 320)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $brushes = @{}
    $eyePen = $null
    $mouthPen = $null
    $glassesPen = $null
    try {
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        foreach ($key in @('Background', 'Halo', 'Skin', 'Hair', 'Shirt')) {
            $brushes[$key] = [System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml($person[$key]))
        }
        $white = [System.Drawing.Brushes]::White
        $graphics.Clear([System.Drawing.ColorTranslator]::FromHtml($person.Background))
        $graphics.FillEllipse($brushes.Halo, 32, 22, 256, 256)
        $graphics.FillEllipse($brushes.Shirt, 46, 219, 228, 220)
        if ($person.Style -eq 0) { $graphics.FillEllipse($brushes.Hair, 88, 66, 145, 202) }
        $graphics.FillRectangle($brushes.Skin, 139, 190, 42, 56)
        $graphics.FillEllipse($brushes.Skin, 131, 224, 58, 30)
        $graphics.FillEllipse($brushes.Hair, 94, 51, 133, 159)
        $graphics.FillEllipse($brushes.Skin, 96, 137, 24, 36)
        $graphics.FillEllipse($brushes.Skin, 202, 137, 24, 36)
        $graphics.FillEllipse($brushes.Skin, 107, 79, 106, 137)
        if ($person.Style -eq 1) {
            $graphics.FillEllipse($brushes.Hair, 92, 48, 136, 81)
            foreach ($x in @(101, 122, 143, 164, 185)) { $graphics.FillEllipse($brushes.Hair, $x, 39, 37, 45) }
        } elseif ($person.Style -eq 2) {
            $graphics.FillEllipse($brushes.Hair, 96, 50, 129, 66)
            $graphics.FillEllipse($brushes.Hair, 104, 71, 44, 65)
        } elseif ($person.Style -eq 3) {
            $graphics.FillEllipse($brushes.Hair, 97, 55, 125, 58)
        } else {
            $graphics.FillEllipse($brushes.Hair, 93, 53, 75, 107)
            $graphics.FillEllipse($brushes.Hair, 153, 52, 72, 59)
        }
        $eyePen = [System.Drawing.Pen]::new([System.Drawing.ColorTranslator]::FromHtml('#302B35'), 4)
        $eyePen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $eyePen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
        $graphics.DrawLine($eyePen, 133, 149, 140, 149)
        $graphics.DrawLine($eyePen, 180, 149, 187, 149)
        $mouthPen = [System.Drawing.Pen]::new([System.Drawing.ColorTranslator]::FromHtml('#864D48'), 3)
        $graphics.DrawArc($mouthPen, 145, 170, 31, 16, 10, 160)
        if ($person.Style -eq 3) {
            $glassesPen = [System.Drawing.Pen]::new([System.Drawing.ColorTranslator]::FromHtml('#3D4350'), 3)
            $graphics.DrawRectangle($glassesPen, 120, 137, 33, 24)
            $graphics.DrawRectangle($glassesPen, 168, 137, 33, 24)
            $graphics.DrawLine($glassesPen, 153, 145, 168, 145)
        }
        $graphics.FillPolygon($white, [System.Drawing.Point[]]@(
            [System.Drawing.Point]::new(130, 227),
            [System.Drawing.Point]::new(151, 248),
            [System.Drawing.Point]::new(126, 259)
        ))
        $graphics.FillPolygon($white, [System.Drawing.Point[]]@(
            [System.Drawing.Point]::new(190, 227),
            [System.Drawing.Point]::new(169, 248),
            [System.Drawing.Point]::new(194, 259)
        ))
        $bitmap.Save((Join-Path $assets "contributor-$($index + 1).jpg"), [System.Drawing.Imaging.ImageFormat]::Jpeg)
    } finally {
        foreach ($brush in $brushes.Values) { $brush.Dispose() }
        if ($eyePen) { $eyePen.Dispose() }
        if ($mouthPen) { $mouthPen.Dispose() }
        if ($glassesPen) { $glassesPen.Dispose() }
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}
Write-Output 'Generated four original 320 x 320 JPEG mock portraits.'
