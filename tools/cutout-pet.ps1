<#
  桌宠立绘抠图（一体化）
  ------------------------------------------------------------------
  把一张「白底 + 人物 + 气泡」的表情包，拆成：
    <prefix>-character.png        人物层（透明，气泡已去掉，原画布）
    <prefix>-bubble.png           气泡层（透明，含文字与尾巴小圆点）
    <prefix>-character-trim.png   人物裁到内容边界
    <prefix>-preview.png          棋盘格预览（确认是真透明）
  之后可再用 Make-Portrait 生成统一 512 画布版本（见文件末尾注释）。

  用法：
    powershell -File tools\cutout-pet.ps1 -In "D:\pic\si.jpg" -OutDir ".\siqu\assets" -Portrait
#>
param(
  [Parameter(Mandatory = $true)][string]$In,
  [Parameter(Mandatory = $true)][string]$OutDir,
  [string]$Prefix = 'siqu',
  [int]$WhiteThreshold = 228,
  [int]$BubbleDepth = 12,
  [switch]$NoBubble,
  [switch]$Portrait
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$nodeScript = Join-Path $here 'cutout.js'
if (-not (Test-Path $nodeScript)) { throw "缺少 $nodeScript" }
if (-not (Test-Path $In)) { throw "找不到输入文件：$In" }

$tmp = Join-Path $OutDir '.tmp'
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

# ---- 1) JPEG/PNG 一律解码成 32bpp BGRA 原始像素 ----
$img = [System.Drawing.Bitmap]::FromFile((Resolve-Path $In).Path)
$bmp = New-Object System.Drawing.Bitmap($img.Width, $img.Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.DrawImage($img, 0, 0, $img.Width, $img.Height)
$g.Dispose()
$img.Dispose()

$rect = New-Object System.Drawing.Rectangle(0, 0, $bmp.Width, $bmp.Height)
$data = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$bytes = New-Object byte[] ($data.Stride * $data.Height)
[System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $bytes.Length)
$bmp.UnlockBits($data)
$w = $bmp.Width; $h = $bmp.Height; $bmp.Dispose()

[IO.File]::WriteAllBytes((Join-Path $tmp 'raw.bin'), $bytes)
@{ width = $w; height = $h; stride = $data.Stride } | ConvertTo-Json |
  Set-Content (Join-Path $tmp 'meta.json') -Encoding ASCII

# ---- 2) 像素处理交给 Node ----
$env:WHITE_THRESHOLD = $WhiteThreshold
$env:BUBBLE_DEPTH = $BubbleDepth
if ($NoBubble) { $env:NO_BUBBLE = '1' } else { Remove-Item Env:\NO_BUBBLE -ErrorAction SilentlyContinue }
& node $nodeScript (Join-Path $tmp 'raw.bin') (Join-Path $tmp 'meta.json') $OutDir $Prefix
if ($LASTEXITCODE -ne 0) { throw "抠图失败（node 退出码 $LASTEXITCODE）" }

# ---- 3) 可选：生成 512 统一画布 ----
if ($Portrait) {
  $trim = Join-Path $OutDir "$Prefix-character-trim.png"
  $src = [System.Drawing.Image]::FromFile($trim)
  $H = 512
  $W = [int][math]::Round($src.Width * $H / $src.Height)
  $canvas = New-Object System.Drawing.Bitmap(512, 512, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $gg = [System.Drawing.Graphics]::FromImage($canvas)
  $gg.InterpolationMode  = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $gg.PixelOffsetMode    = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $gg.SmoothingMode      = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
  $gg.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
  $dx = [int]((512 - $W) / 2)
  $gg.DrawImage($src, (New-Object System.Drawing.Rectangle($dx, 0, $W, $H)))
  $gg.Dispose()
  $canvas.Save((Join-Path $OutDir "$Prefix-portrait-512.png"), [System.Drawing.Imaging.ImageFormat]::Png)
  $canvas.Dispose(); $src.Dispose()
  "已生成 512 画布版：$Prefix-portrait-512.png"
}

Remove-Item $tmp -Recurse -Force
Get-ChildItem $OutDir -Filter "$Prefix-*.png" | Select-Object Name, Length | Format-Table -AutoSize
