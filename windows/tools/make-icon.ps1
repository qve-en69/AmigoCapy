# Рисует windows\AmigoClick.ico (256/64/48/32/24/16 px, PNG внутри ICO).
# Запуск: powershell -ExecutionPolicy Bypass -File windows\tools\make-icon.ps1
Add-Type -AssemblyName System.Drawing

$out = Join-Path $PSScriptRoot '..\AmigoClick.ico'
$sizes = 256, 64, 48, 32, 24, 16

function New-IconPng([int]$size) {
    $bmp = New-Object System.Drawing.Bitmap $size, $size
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.PixelOffsetMode = 'HighQuality'

    # Плитка с градиентом
    $pad = [Math]::Max(1, $size * 0.04)
    $tile = New-Object System.Drawing.RectangleF $pad, $pad, ($size - 2 * $pad), ($size - 2 * $pad)
    $r = $tile.Width * 0.24
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddArc($tile.X, $tile.Y, 2 * $r, 2 * $r, 180, 90)
    $path.AddArc($tile.Right - 2 * $r, $tile.Y, 2 * $r, 2 * $r, 270, 90)
    $path.AddArc($tile.Right - 2 * $r, $tile.Bottom - 2 * $r, 2 * $r, 2 * $r, 0, 90)
    $path.AddArc($tile.X, $tile.Bottom - 2 * $r, 2 * $r, 2 * $r, 90, 90)
    $path.CloseFigure()
    $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush $tile, ([System.Drawing.Color]::FromArgb(255, 41, 204, 158)), ([System.Drawing.Color]::FromArgb(255, 38, 133, 242)), 45.0
    $g.FillPath($brush, $path)

    # Курсор и «вспышка» клика в координатах 0..100 (как CursorGeometry в App.xaml)
    $k = $size / 100.0
    $m = New-Object System.Drawing.Drawing2D.Matrix
    $m.Translate($size * 0.06, $size * 0.06)
    $m.Scale($k * 0.95, $k * 0.95)
    $g.Transform = $m

    $pts = @(
        (New-Object System.Drawing.PointF 40, 26), (New-Object System.Drawing.PointF 40, 72),
        (New-Object System.Drawing.PointF 52, 61), (New-Object System.Drawing.PointF 60, 80),
        (New-Object System.Drawing.PointF 68, 77), (New-Object System.Drawing.PointF 60, 58),
        (New-Object System.Drawing.PointF 76, 58))
    $g.FillPolygon([System.Drawing.Brushes]::White, [System.Drawing.PointF[]]$pts)

    $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::White), 5
    $pen.StartCap = 'Round'; $pen.EndCap = 'Round'
    $g.DrawLine($pen, 33, 19, 25, 11)
    $g.DrawLine($pen, 40, 16, 40, 5)
    $g.DrawLine($pen, 30, 26, 19, 26)

    $g.Dispose()
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    return , $ms.ToArray()
}

$images = foreach ($s in $sizes) { , (New-IconPng $s) }

$fs = [System.IO.File]::Create($out)
$w = New-Object System.IO.BinaryWriter $fs
$w.Write([UInt16]0); $w.Write([UInt16]1); $w.Write([UInt16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $s = $sizes[$i]; $data = $images[$i]
    $dim = if ($s -ge 256) { 0 } else { $s }
    $w.Write([byte]$dim); $w.Write([byte]$dim); $w.Write([byte]0); $w.Write([byte]0)
    $w.Write([UInt16]1); $w.Write([UInt16]32)
    $w.Write([UInt32]$data.Length); $w.Write([UInt32]$offset)
    $offset += $data.Length
}
foreach ($data in $images) { $w.Write($data) }
$w.Close()
Write-Host "Saved $out"
