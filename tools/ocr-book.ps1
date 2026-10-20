<#
  教材 PDF 批量 OCR
  ------------------------------------------------------------------
  你的教材是扫描版（每页一张图），没有文字层，所以只能 OCR。
  用系统自带的 Windows.Media.Ocr（简体中文），实测约 0.2 秒/页。

  流程：PyMuPDF 渲染成图（每 30 页一批）→ Windows OCR → 写 pages\pNNN.txt → 删图

  用法：
    powershell -ExecutionPolicy Bypass -File tools\ocr-book.ps1 -Pdf "课本.pdf" -Out siqu\textbook
    ... -From 1 -To 20       只做前 20 页（快速试跑）
    ... -Dpi 250             识别不清时提高分辨率

  可断点续跑：已经存在的 pNNN.txt 会跳过。
#>
param(
  [Parameter(Mandatory = $true)][string]$Pdf,
  [Parameter(Mandatory = $true)][string]$Out,
  [int]$From = 1,
  [int]$To = 0,
  [int]$Dpi = 200,
  [int]$Chunk = 30
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Runtime.WindowsRuntime

if (-not (Test-Path $Pdf)) { throw "找不到 PDF：$Pdf" }
$pagesDir = Join-Path $Out 'pages'
$tmpDir = Join-Path $Out '.tmp-img'
New-Item -ItemType Directory -Path $pagesDir -Force | Out-Null
New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null

# ---- WinRT 异步等待 ----
$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
  $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
  $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
})[0]
function Await($op, $type) {
  $t = $asTaskGeneric.MakeGenericMethod($type).Invoke($null, @($op))
  $t.Wait(-1) | Out-Null
  $t.Result
}

$null = [Windows.Storage.StorageFile, Windows.Foundation, ContentType = WindowsRuntime]
$null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Foundation, ContentType = WindowsRuntime]
$null = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]

$engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
if (-not $engine) { throw "系统没有可用的 OCR 引擎（需要中文语言包）" }

# ---- 总页数 ----
$pyCount = @"
import fitz
d = fitz.open(r'$Pdf')
print(d.page_count)
d.close()
"@
$tmpPy = Join-Path $tmpDir 'count.py'
[IO.File]::WriteAllText($tmpPy, $pyCount, (New-Object Text.UTF8Encoding($false)))
$totalPages = [int](& py -3 $tmpPy 2>&1 | Select-Object -First 1)
if ($To -le 0 -or $To -gt $totalPages) { $To = $totalPages }

Write-Host ""
Write-Host "  PDF: $Pdf" -ForegroundColor DarkGray
Write-Host "  页数: $totalPages   处理范围: $From - $To   DPI: $Dpi" -ForegroundColor DarkGray
Write-Host "  OCR 引擎: $($engine.RecognizerLanguage.LanguageTag)" -ForegroundColor DarkGray
Write-Host ""

$done = 0; $skipped = 0; $failed = 0
$swAll = [System.Diagnostics.Stopwatch]::StartNew()

for ($start = $From; $start -le $To; $start += $Chunk) {
  $end = [Math]::Min($start + $Chunk - 1, $To)

  # 这一批里是否已经有结果（续跑）
  $need = @()
  for ($p = $start; $p -le $end; $p++) {
    $f = Join-Path $pagesDir ("p{0:d3}.txt" -f $p)
    if (Test-Path $f) { $skipped++ } else { $need += $p }
  }
  if ($need.Count -eq 0) { continue }

  # 渲染这批
  $ranges = ($need | ForEach-Object { $_ }) -join ','
  $pyRender = @"
import fitz
doc = fitz.open(r'$Pdf')
for pno in [$ranges]:
    pix = doc[pno-1].get_pixmap(dpi=$Dpi)
    pix.save(rf'$tmpDir\pg-{pno:03d}.jpg', jpg_quality=88)
doc.close()
"@
  $tmpRender = Join-Path $tmpDir 'render.py'
  [IO.File]::WriteAllText($tmpRender, $pyRender, (New-Object Text.UTF8Encoding($false)))
  & py -3 $tmpRender 2>&1 | Out-Null

  # OCR 这批
  foreach ($p in $need) {
    $img = Join-Path $tmpDir ("pg-{0:d3}.jpg" -f $p)
    if (-not (Test-Path $img)) { $failed++; continue }
    try {
      $file = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($img)) ([Windows.Storage.StorageFile])
      $stream = Await ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
      $decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
      $bmp = Await ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
      $res = Await ($engine.RecognizeAsync($bmp)) ([Windows.Media.Ocr.OcrResult])

      # 按行输出（保留版面结构，后面 Python 再清洗）
      $lines = @()
      foreach ($ln in $res.Lines) { $lines += $ln.Text }
      $text = ($lines -join "`n")
      [IO.File]::WriteAllText((Join-Path $pagesDir ("p{0:d3}.txt" -f $p)), $text, (New-Object Text.UTF8Encoding($false)))
      $done++
    } catch {
      $failed++
      Write-Host "    p$p OCR 失败: $($_.Exception.Message)" -ForegroundColor DarkYellow
    }
    # 及时关闭句柄
    if ($stream) { $stream.Dispose() }
  }

  # 删本批图片
  foreach ($p in $need) { Remove-Item (Join-Path $tmpDir ("pg-{0:d3}.jpg" -f $p)) -Force -ErrorAction SilentlyContinue }

  $el = [Math]::Round($swAll.Elapsed.TotalSeconds, 1)
  Write-Host ("  已完成 {0}/{1}  (用时 {2}s)" -f ($done + $skipped), ($To - $From + 1), $el) -ForegroundColor DarkGray
}

$swAll.Stop()
Write-Host ""
Write-Host ("  OCR 完成：新增 {0} 页，跳过 {1} 页，失败 {2} 页，总用时 {3:N1}s" -f $done, $skipped, $failed, $swAll.Elapsed.TotalSeconds) -ForegroundColor Green
Write-Host ("  输出：{0}" -f $pagesDir) -ForegroundColor DarkGray
Write-Host ""
