Add-Type -AssemblyName System.Drawing

$srcPath = Join-Path (Get-Location) "assets/images/logo.png"
$dstPath = Join-Path (Get-Location) "assets/images/splash_logo.png"

$src = [System.Drawing.Image]::FromFile($srcPath)
$canvas = New-Object System.Drawing.Bitmap(1024, 1024)
$g = [System.Drawing.Graphics]::FromImage($canvas)
$g.Clear([System.Drawing.Color]::Transparent)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
$g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

$targetW = 500
$targetH = [int]($targetW * $src.Height / $src.Width)
$posX = [int]((1024 - $targetW) / 2)
$posY = [int]((1024 - $targetH) / 2)

$g.DrawImage($src, $posX, $posY, $targetW, $targetH)
$g.Dispose()
$src.Dispose()

$canvas.Save($dstPath, [System.Drawing.Imaging.ImageFormat]::Png)
$canvas.Dispose()

Write-Output "Successfully created splash_logo.png (1024x1024 with 500x408 centered logo)"
