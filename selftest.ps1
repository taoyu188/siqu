<#
  siqu 自检 —— 验证「编译诊断」模块是否正常
  ------------------------------------------------------------------
  直接跑，不需要桌宠窗口：
      powershell -ExecutionPolicy Bypass -File siqu\selftest.ps1

  它会用 gcc-shim 编译 6 个样例文件（5 个故意写错、1 个正确），
  然后用 diagnose.js 分析日志，检查每条规则是否正确命中。
#>
param(
  [switch]$KeepLog
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$testDir = Join-Path $root 'test'
$shim    = Join-Path $root 'build\gcc-shim.exe'
$diag    = Join-Path $root 'core\diagnose.js'
$log     = Join-Path $testDir 'build.log'

if (-not (Test-Path $shim)) {
  throw "找不到 $shim（先用 gcc 编译：gcc build\gcc-shim.c -o build\gcc-shim.exe -O2）"
}

# ---- 找 gcc（优先 Dev-C++ 自带的，和 IDE 行为一致）----
$candidates = @(
  'D:\Dev-Cpp\MinGW64\bin\gcc.exe',
  'D:\min\mingw64\bin\gcc.exe',
  'C:\Program Files\Dev-Cpp\MinGW64\bin\gcc.exe'
)
$gcc = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $gcc) {
  $cmd = Get-Command gcc -ErrorAction SilentlyContinue
  if ($cmd) { $gcc = $cmd.Source }
}
if (-not $gcc) { throw "找不到 gcc.exe。请手动设置 SIQU_REAL_GCC 环境变量指向你的 gcc。" }

Write-Host ""
Write-Host "  编译诊断自检" -ForegroundColor Cyan
Write-Host "  gcc    : $gcc" -ForegroundColor DarkGray
Write-Host "  日志   : $log" -ForegroundColor DarkGray
Write-Host ""

$env:SIQU_REAL_GCC = $gcc
$env:SIQU_LOG = $log
if (Test-Path $log) { Remove-Item $log -Force }

$cases = @(
  @{ f = 't1.c'; desc = '少分号';              want = 'missing-semicolon' }
  @{ f = 't3.c'; desc = '忘 include (-Wall)';  want = 'implicit-declaration'; extra = '-Wall' }
  @{ f = 't4.c'; desc = '全角分号';            want = 'fullwidth-char' }
  @{ f = 't5.c'; desc = '浮点取模';            want = 'mod-float' }
  @{ f = 't6.c'; desc = 'scanf 缺 & (-Wall)';  want = 'scanf-missing-amp';    extra = '-Wall' }
  @{ f = 't7.c'; desc = 'for 里声明(gnu90)';   want = 'c99-for-loop'; extra = '-std=gnu90' }
  @{ f = 'ok.c'; desc = '正常代码（应通过）';   want = $null }
)

$results = @()
foreach ($c in $cases) {
  $src = Join-Path $testDir $c.f
  if (-not (Test-Path $src)) { Write-Host "  跳过（缺文件）$($c.f)" -ForegroundColor Yellow; continue }
  $obj = Join-Path $testDir "$($c.f).o"
  $extraArgs = @()
  if ($c.extra) { $extraArgs = $c.extra.Split(' ') }
  # PS5.1 会把原生程序的 stderr 当成 ErrorRecord，在 Stop 下会终止脚本，
  # 所以这一段临时切到 Continue。
  $prev = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  & $shim @extraArgs -c $src -o $obj 2>&1 | Out-Null
  $code = $LASTEXITCODE
  $ErrorActionPreference = $prev
  $results += [pscustomobject]@{ File = $c.f; Desc = $c.desc; Exit = $code; Want = $c.want }
}

Write-Host "  ── 编译结果 ──────────────────────────────" -ForegroundColor DarkGray
foreach ($r in $results) {
  $color = if ($r.Exit -eq 0) { 'Green' } else { 'Yellow' }
  Write-Host ("  {0,-6} {1,-22} exit={2}" -f $r.File, $r.Desc, $r.Exit) -ForegroundColor $color
}

Write-Host ""
Write-Host "  ── 诊断输出 ──────────────────────────────" -ForegroundColor DarkGray
& node $diag --file $log --all

# ---- 校验：每条应命中的规则都真的命中了 ----
Write-Host ""
Write-Host "  ── 规则命中检查 ──────────────────────────" -ForegroundColor DarkGray
$json = & node $diag --file $log --all --json | ConvertFrom-Json
$pass = 0; $fail = 0
foreach ($r in $results) {
  if (-not $r.Want) {
    $rec = $json | Where-Object { (Split-Path "$($_.source)" -Leaf) -eq $r.File } | Select-Object -First 1
    if ($rec -and $rec.ok) { Write-Host ("  [OK]   {0,-6} 正确识别为编译通过" -f $r.File) -ForegroundColor Green; $pass++ }
    else { Write-Host ("  [FAIL] {0,-6} 应该通过却报了错" -f $r.File) -ForegroundColor Red; $fail++ }
    continue
  }
  $rec = $json | Where-Object { (Split-Path "$($_.source)" -Leaf) -eq $r.File } | Select-Object -First 1
  $ids = @($rec.hits | ForEach-Object { $_.id })
  if ($ids -contains $r.Want) {
    Write-Host ("  [OK]   {0,-6} 命中 {1}" -f $r.File, $r.Want) -ForegroundColor Green; $pass++
  } else {
    Write-Host ("  [FAIL] {0,-6} 期望 {1}，实际 [{2}]" -f $r.File, $r.Want, ($ids -join ', ')) -ForegroundColor Red; $fail++
  }
}

Write-Host ""
if ($fail -eq 0) {
  Write-Host "  全部通过：$pass 项" -ForegroundColor Green
} else {
  Write-Host "  通过 $pass 项，失败 $fail 项" -ForegroundColor Red
}

if (-not $KeepLog) { Remove-Item $log -Force -ErrorAction SilentlyContinue }
Write-Host ""
