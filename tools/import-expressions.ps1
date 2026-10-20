<#
  把 7 张表情素材处理成桌宠可用的状态图
  ------------------------------------------------------------------
  流程（每张）：可选去水印 → 抠掉白底 → 裁到内容 → 归一化到 512 画布（底对齐）
  产物：siqu\assets\siqu-<state>.png

  用法：powershell -ExecutionPolicy Bypass -File tools\import-expressions.ps1
#>
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$root    = Split-Path -Parent $MyInvocation.MyCommand.Path      # tools
$appRoot = Split-Path -Parent $root                             # 工作区
$siqu    = Join-Path $appRoot 'siqu'
$assets  = Join-Path $siqu 'assets'
$tmp     = Join-Path $siqu 'test\expr-tmp'
$cutout  = Join-Path $root 'cutout-pet.ps1'

New-Item -ItemType Directory -Path $assets -Force | Out-Null
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

$att = 'C:\Users\john\.dsh\attachments\v1\objects'

# 素材 → 情绪槽位（用户给的顺序）
$jobs = @(
  @{ state = 'happy';       src = "$att\f1\f12e573d1c6c26481a5f669c3e2b75253c9c65c26b3e5a6c3084046d623cb28c"; wm = $false }
  @{ state = 'taunt';       src = "$att\ec\ec9b0bfa2aedb14f299251bf1719cd2fb274cc0384bc6fb22e29fc7f4dd41404"; wm = $false }
  @{ state = 'confused';    src = "$att\e4\e473e1bdafbaa8279ca35bc631d369c390a8481f3de7f3c7542d0c25100ada84"; wm = $false }
  @{ state = 'embarrassed'; src = "$att\34\340d65a2aa35ff47b5032a71b4e8b68c429f9e931dc6d390ec740387e98957de"; wm = $false }
  @{ state = 'jealous';     src = "$att\55\556dc719c6c1819930333670cf266735ba42fe5773da370c3d5a17a4a48994b1"; wm = $false }
  @{ state = 'pout';        src = "$att\85\85861241e8cae82a4d6f2a8e7450352a6658c0db0cb1b4fb30e08f4094d33777"; wm = $false }
  @{ state = 'sleep';       src = "$att\4f\4f152bfdb420230fedbd96fbc67373ae495318fe2c74a8c5ccf674f05abdf41d"; wm = $true  }
)

# ---------------- 去水印：邻域迭代填充 ----------------
function Remove-Watermark {
  param([string]$InPath, [string]$OutPath,
        [int]$X0, [int]$Y0, [int]$X1, [int]$Y1)

  $bmp = [System.Drawing.Bitmap]::FromFile($InPath)
  $w = $bmp.Width; $h = $bmp.Height
  $bmp2 = New-Object System.Drawing.Bitmap -ArgumentList $w, $h, ([System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
  $g = [System.Drawing.Graphics]::FromImage($bmp2)
  $g.DrawImage($bmp, 0, 0, $w, $h)
  $g.Dispose(); $bmp.Dispose()

  $X0 = [Math]::Max(0, $X0); $Y0 = [Math]::Max(0, $Y0)
  $X1 = [Math]::Min($w - 1, $X1); $Y1 = [Math]::Min($h - 1, $Y1)
  $rw = $X1 - $X0 + 1; $rh = $Y1 - $Y0 + 1

  # 取区域到内存
  $px = New-Object 'int[,]' $rw, $rh
  $mask = New-Object 'bool[,]' $rw, $rh
  for ($y = 0; $y -lt $rh; $y++) {
    for ($x = 0; $x -lt $rw; $x++) {
      $c = $bmp2.GetPixel($X0 + $x, $Y0 + $y)
      $mx = [Math]::Max($c.R, [Math]::Max($c.G, $c.B))
      $mn = [Math]::Min($c.R, [Math]::Min($c.G, $c.B))
      $bright = [int](($c.R + $c.G + $c.B) / 3)
      # 灰色文字：低饱和 + 中高亮度（白底 245+ 和深色头发 90- 都被排除）
      $isWm = (($mx - $mn) -le 22) -and ($bright -ge 105) -and ($bright -le 238)
      if ($isWm) { $mask[$x, $y] = $true }
      $px[$x, $y] = (([int]$c.R -shl 16) -bor ([int]$c.G -shl 8) -bor [int]$c.B)
    }
  }

  # 迭代填充：有 >=2 个已知邻居就取均值
  for ($iter = 0; $iter -lt 24; $iter++) {
    $changed = 0
    for ($y = 0; $y -lt $rh; $y++) {
      for ($x = 0; $x -lt $rw; $x++) {
        if (-not $mask[$x, $y]) { continue }
        $sr = 0; $sg = 0; $sb = 0; $cnt = 0
        for ($dy = -1; $dy -le 1; $dy++) {
          for ($dx = -1; $dx -le 1; $dx++) {
            if ($dx -eq 0 -and $dy -eq 0) { continue }
            $nx = $x + $dx; $ny = $y + $dy
            if ($nx -lt 0 -or $ny -lt 0 -or $nx -ge $rw -or $ny -ge $rh) { continue }
            if ($mask[$nx, $ny]) { continue }
            $v = $px[$nx, $ny]
            $sr += (($v -shr 16) -band 0xFF); $sg += (($v -shr 8) -band 0xFF); $sb += ($v -band 0xFF)
            $cnt++
          }
        }
        if ($cnt -ge 2) {
          $r = [int]($sr / $cnt); $gg = [int]($sg / $cnt); $bb = [int]($sb / $cnt)
          $px[$x, $y] = (($r -shl 16) -bor ($gg -shl 8) -bor $bb)
          $mask[$x, $y] = $false
          $changed++
        }
      }
    }
    if ($changed -eq 0) { break }
  }

  # 写回
  for ($y = 0; $y -lt $rh; $y++) {
    for ($x = 0; $x -lt $rw; $x++) {
      $v = [int]$px[$x, $y]
      $rr = [int](($v -shr 16) -band 0xFF)
      $gg = [int](($v -shr 8) -band 0xFF)
      $bb = [int]($v -band 0xFF)
      $bmp2.SetPixel($X0 + $x, $Y0 + $y, [System.Drawing.Color]::FromArgb($rr, $gg, $bb))
    }
  }
  $bmp2.Save($OutPath, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp2.Dispose()
  return ($mask | Where-Object { $_ } | Measure-Object).Count
}

# ---------------- 归一化到 512 画布（底对齐居中） ----------------
function Normalize-512 {
  param([string]$InPath, [string]$OutPath)
  $src = [System.Drawing.Bitmap]::FromFile($InPath)
  $sw = $src.Width; $sh = $src.Height

  # 先找到内容边界（非全透明）
  $minX = $sw; $minY = $sh; $maxX = -1; $maxY = -1
  for ($y = 0; $y -lt $sh; $y += 2) {
    for ($x = 0; $x -lt $sw; $x += 2) {
      if ($src.GetPixel($x, $y).A -gt 8) {
        if ($x -lt $minX) { $minX = $x }; if ($x -gt $maxX) { $maxX = $x }
        if ($y -lt $minY) { $minY = $y }; if ($y -gt $maxY) { $maxY = $y }
      }
    }
  }
  if ($maxX -lt 0) { $src.Dispose(); throw "归一化失败，图片全透明：$InPath" }
  $cw = $maxX - $minX + 1; $chh = $maxY - $minY + 1

  # 以内容【宽度】为基准：这几张都是同一角色的半身/头像，
  # 发型展开的宽度比高度稳定（有的图下半身被裁掉了，按高度会对不齐）
  $targetW = 360
  $scale = $targetW / $cw
  $dw = $targetW
  $dh = [int][Math]::Round($chh * $scale)
  if ($dh -gt 500) {
    $scale = 500.0 / $chh
    $dw = [int][Math]::Round($cw * $scale)
    $dh = 500
  }

  $canvas = New-Object System.Drawing.Bitmap -ArgumentList 512, 512, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $gg = [System.Drawing.Graphics]::FromImage($canvas)
  $gg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $gg.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $gg.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
  $gg.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
  # 半身像按【头顶】对齐：这些素材都是"头 + 肩"，下半身裁切位置各不相同，
  # 按底对齐会让头上下跳；按头顶对齐才稳定。
  $dx = [int](512 - $dw) / 2
  $dy = 8
  $dst = New-Object System.Drawing.Rectangle -ArgumentList $dx, $dy, $dw, $dh
  $srcRect = New-Object System.Drawing.Rectangle -ArgumentList $minX, $minY, $cw, $chh
  $gg.DrawImage($src, $dst, $srcRect, [System.Drawing.GraphicsUnit]::Pixel)
  $gg.Dispose()
  $canvas.Save($OutPath, [System.Drawing.Imaging.ImageFormat]::Png)
  $canvas.Dispose(); $src.Dispose()
  return "内容 ${cw}x${chh} → 缩放后 ${dw}x${dh}，放于 ($dx,$dy)"
}

# ---------------- 主流程 ----------------
Write-Host ""
Write-Host "  处理表情素材" -ForegroundColor Cyan
Write-Host ""

foreach ($j in $jobs) {
  $state = $j.state
  $srcPath = $j.src
  if (-not (Test-Path $srcPath)) { Write-Host "  [$state] 找不到源文件，跳过" -ForegroundColor Yellow; continue }

  $work = $srcPath

  if ($j.wm) {
    $wmOut = Join-Path $tmp "$state-nowm.png"
    $left = Remove-Watermark -InPath $srcPath -OutPath $wmOut -X0 330 -Y0 515 -X1 505 -Y1 640
    Write-Host ("  [{0}] 去水印：残留掩码 {1} 像素" -f $state, $left) -ForegroundColor DarkGray
    $work = $wmOut
  }

  $outDir = Join-Path $tmp $state
  & $cutout -In $work -OutDir $outDir -Prefix $state -NoBubble | Out-Null
  $trim = Join-Path $outDir "$state-character-trim.png"
  if (-not (Test-Path $trim)) { Write-Host "  [$state] 抠图失败" -ForegroundColor Red; continue }

  $final = Join-Path $assets "siqu-$state.png"
  $info = Normalize-512 -InPath $trim -OutPath $final
  Write-Host ("  [{0}] OK  {1}" -f $state, $info) -ForegroundColor Green
}

# idle：用最初抠好的透明立绘，走同一套归一化，保证和表情图构图一致
$idleSrc = Join-Path $assets 'siqu-character.png'
if (Test-Path $idleSrc) {
  $idleOut = Join-Path $assets 'siqu-idle.png'
  $info = Normalize-512 -InPath $idleSrc -OutPath $idleOut
  Write-Host ("  [idle] OK  {0}" -f $info) -ForegroundColor Green
}

Write-Host ""
Get-ChildItem $assets -Filter 'siqu-*.png' | Select-Object Name, @{n='KB';e={[math]::Round($_.Length/1KB,1)}} | Format-Table -AutoSize
