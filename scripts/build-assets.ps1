param(
    [string]$BaseAvatarPath = "",
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
if (-not $BaseAvatarPath) {
    $BaseAvatarPath = Join-Path $root "assets\notifu-chibi-avatar-cutout.png"
}
if (-not $OutputDir) {
    $OutputDir = Join-Path $root "assets"
}

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

if (-not (Test-Path -LiteralPath $BaseAvatarPath)) {
    throw "Base avatar not found: $BaseAvatarPath"
}
if (-not (Test-Path -LiteralPath $OutputDir)) {
    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
}

function New-CopyBitmap {
    param([System.Drawing.Bitmap]$Source)

    $copy = New-Object System.Drawing.Bitmap $Source.Width, $Source.Height, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($copy)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.DrawImage($Source, 0, 0, $Source.Width, $Source.Height)
    $graphics.Dispose()
    return $copy
}

function Save-Png {
    param(
        [System.Drawing.Bitmap]$Image,
        [string]$Path
    )

    $Image.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
}

function New-RectF {
    param($x, $y, $w, $h)
    return New-Object System.Drawing.RectangleF ([single]$x), ([single]$y), ([single]$w), ([single]$h)
}

function Draw-MouthPatch {
    param(
        [System.Drawing.Graphics]$Graphics,
        [int]$Width,
        [int]$Height
    )

    $skin = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 253, 207, 177))
    $Graphics.FillEllipse($skin, (New-RectF ($Width * 0.438) ($Height * 0.647) ($Width * 0.17) ($Height * 0.12)))
    $skin.Dispose()
}

function Draw-Smile {
    param([System.Drawing.Graphics]$Graphics, [int]$Width, [int]$Height)

    Draw-MouthPatch -Graphics $Graphics -Width $Width -Height $Height
    $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(170, 121, 38, 44)), ([single]($Width * 0.012))
    $Graphics.DrawArc($pen, (New-RectF ($Width * 0.485) ($Height * 0.680) ($Width * 0.075) ($Height * 0.040)), 5, 170)
    $pen.Dispose()
}

function Draw-SmallOpenMouth {
    param([System.Drawing.Graphics]$Graphics, [int]$Width, [int]$Height)

    Draw-MouthPatch -Graphics $Graphics -Width $Width -Height $Height
    $mouth = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(235, 113, 42, 58))
    $highlight = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(245, 255, 151, 138))
    $Graphics.FillEllipse($mouth, (New-RectF ($Width * 0.500) ($Height * 0.675) ($Width * 0.048) ($Height * 0.055)))
    $Graphics.FillEllipse($highlight, (New-RectF ($Width * 0.510) ($Height * 0.708) ($Width * 0.027) ($Height * 0.016)))
    $mouth.Dispose()
    $highlight.Dispose()
}

function Draw-FlatMouth {
    param([System.Drawing.Graphics]$Graphics, [int]$Width, [int]$Height)

    Draw-MouthPatch -Graphics $Graphics -Width $Width -Height $Height
    $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(170, 108, 43, 52)), ([single]($Width * 0.009))
    $Graphics.DrawLine($pen, ([single]($Width * 0.488)), ([single]($Height * 0.698)), ([single]($Width * 0.552)), ([single]($Height * 0.698)))
    $pen.Dispose()
}

function Draw-ClosedEyes {
    param([System.Drawing.Graphics]$Graphics, [int]$Width, [int]$Height)

    $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(225, 62, 41, 45)), ([single]($Width * 0.010))
    $Graphics.DrawArc($pen, (New-RectF ($Width * 0.338) ($Height * 0.610) ($Width * 0.106) ($Height * 0.046)), 12, 160)
    $Graphics.DrawArc($pen, (New-RectF ($Width * 0.585) ($Height * 0.610) ($Width * 0.106) ($Height * 0.046)), 12, 160)
    $pen.Dispose()
}

function Draw-Sparkle {
    param([System.Drawing.Graphics]$Graphics, [int]$Width, [int]$Height)

    $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 255, 201, 77)), ([single]($Width * 0.010))
    $x = [single]($Width * 0.750)
    $y = [single]($Height * 0.585)
    $r = [single]($Width * 0.028)
    $Graphics.DrawLine($pen, $x, ($y - $r), $x, ($y + $r))
    $Graphics.DrawLine($pen, ($x - $r), $y, ($x + $r), $y)
    $pen.Dispose()
}

function Draw-SweatDrop {
    param([System.Drawing.Graphics]$Graphics, [int]$Width, [int]$Height)

    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $x = [single]($Width * 0.720)
    $y = [single]($Height * 0.565)
    $path.AddBezier($x, $y, ($x + 30), ($y + 48), ($x + 8), ($y + 78), ($x - 18), ($y + 57))
    $path.AddBezier(($x - 18), ($y + 57), ($x - 36), ($y + 31), ($x - 8), ($y + 8), $x, $y)
    $path.CloseFigure()
    $brush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(220, 98, 204, 235))
    $Graphics.FillPath($brush, $path)
    $brush.Dispose()
    $path.Dispose()
}

function Draw-FocusBadge {
    param([System.Drawing.Graphics]$Graphics, [int]$Width, [int]$Height)

    $brush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(238, 255, 242, 184))
    $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(220, 197, 143, 33)), 5
    $rect = New-Object System.Drawing.Rectangle ([int]($Width * 0.710)), ([int]($Height * 0.575)), ([int]($Width * 0.075)), ([int]($Height * 0.060))
    $Graphics.FillRectangle($brush, $rect)
    $Graphics.DrawRectangle($pen, $rect)
    $pen.Dispose()
    $brush.Dispose()
}

function Save-Expression {
    param(
        [System.Drawing.Bitmap]$Base,
        [string]$Name,
        [scriptblock]$Draw
    )

    $bitmap = New-CopyBitmap -Source $Base
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    & $Draw $graphics $bitmap.Width $bitmap.Height
    $graphics.Dispose()
    Save-Png -Image $bitmap -Path (Join-Path $OutputDir "notifu-expression-$Name.png")
    $bitmap.Dispose()
}

function Save-Icon {
    param([System.Drawing.Bitmap]$Base)

    $iconBitmap = New-Object System.Drawing.Bitmap 256, 256, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($iconBitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.Clear([System.Drawing.Color]::Transparent)
    $iconRect = New-Object System.Drawing.Rectangle 0, 0, 256, 256
    $bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush -ArgumentList @(
        $iconRect,
        ([System.Drawing.Color]::FromArgb(255, 28, 144, 140)),
        ([System.Drawing.Color]::FromArgb(255, 255, 184, 108)),
        45
    )
    $graphics.FillEllipse($bg, 12, 12, 232, 232)
    $graphics.DrawImage($Base, (New-Object System.Drawing.Rectangle 24, 18, 208, 208))
    $bg.Dispose()
    $graphics.Dispose()

    $pngPath = Join-Path $OutputDir "notifu-app-icon.png"
    Save-Png -Image $iconBitmap -Path $pngPath

    $handle = $iconBitmap.GetHicon()
    $icon = [System.Drawing.Icon]::FromHandle($handle)
    $stream = [System.IO.File]::Open((Join-Path $OutputDir "notifu-app-icon.ico"), [System.IO.FileMode]::Create)
    try {
        $icon.Save($stream)
    } finally {
        $stream.Dispose()
        $icon.Dispose()
        $iconBitmap.Dispose()
    }
}

function Save-QrisPlaceholder {
    $path = Join-Path $OutputDir "support-qris-placeholder.png"
    $bitmap = New-Object System.Drawing.Bitmap 640, 640, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.Clear([System.Drawing.Color]::White)
    $black = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 34, 34, 34))
    $gray = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 240, 240, 240))
    $font = New-Object System.Drawing.Font "Segoe UI Semibold", 24
    $smallFont = New-Object System.Drawing.Font "Segoe UI", 14

    $graphics.DrawString("QRIS support placeholder", $font, $black, 80, 36)
    $graphics.DrawString("Replace this PNG with the developer's official QRIS before release.", $smallFont, $black, 64, 84)
    $graphics.FillRectangle($gray, 120, 150, 400, 400)

    for ($row = 0; $row -lt 25; $row++) {
        for ($col = 0; $col -lt 25; $col++) {
            $draw = (($row * 17 + $col * 31 + ($row * $col)) % 7) -in @(0, 2, 5)
            if ($draw) {
                $graphics.FillRectangle($black, 132 + ($col * 15), 162 + ($row * 15), 13, 13)
            }
        }
    }

    $graphics.DrawString("NOT AN ACTIVE PAYMENT QR", $font, $black, 118, 570)
    $font.Dispose()
    $smallFont.Dispose()
    $black.Dispose()
    $gray.Dispose()
    $graphics.Dispose()
    Save-Png -Image $bitmap -Path $path
    $bitmap.Dispose()
}

$baseImage = [System.Drawing.Bitmap]::FromFile($BaseAvatarPath)
try {
    Save-Expression -Base $baseImage -Name "happy" -Draw { param($g, $w, $h) Draw-Smile -Graphics $g -Width $w -Height $h }
    Save-Expression -Base $baseImage -Name "talking" -Draw { param($g, $w, $h) Draw-SmallOpenMouth -Graphics $g -Width $w -Height $h; Draw-Sparkle -Graphics $g -Width $w -Height $h }
    Save-Expression -Base $baseImage -Name "curious" -Draw { param($g, $w, $h) Draw-SmallOpenMouth -Graphics $g -Width $w -Height $h }
    Save-Expression -Base $baseImage -Name "focused" -Draw { param($g, $w, $h) Draw-FlatMouth -Graphics $g -Width $w -Height $h; Draw-FocusBadge -Graphics $g -Width $w -Height $h }
    Save-Expression -Base $baseImage -Name "worried" -Draw { param($g, $w, $h) Draw-FlatMouth -Graphics $g -Width $w -Height $h; Draw-SweatDrop -Graphics $g -Width $w -Height $h }
    Save-Expression -Base $baseImage -Name "sleepy" -Draw { param($g, $w, $h) Draw-Smile -Graphics $g -Width $w -Height $h; Draw-ClosedEyes -Graphics $g -Width $w -Height $h }
    Save-Icon -Base $baseImage
    Save-QrisPlaceholder
} finally {
    $baseImage.Dispose()
}

Write-Host "Notifu assets generated in $OutputDir"
