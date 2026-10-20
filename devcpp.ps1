<#
  Dev-C++ 编译器接入 / 还原
  ------------------------------------------------------------------
  用法：
    .\devcpp.ps1 -Off     还原成原装的 gcc（默认动作，最安全）
    .\devcpp.ps1 -On      接入 siqu 的 gcc-shim（会先自动备份）
    .\devcpp.ps1 -Status  只看当前状态，不改任何东西

  原理：
    Dev-C++ 的「程序」栏填的是【文件名】，它会在自己的
    MinGW64\bin 目录里找。所以 shim 必须放进那个目录，
    配置里只写文件名 gcc-shim.exe（不能写完整路径）。

  安全保证：
    * 每次改动前都会备份 devcpp.ini
    * 从不修改、不删除、不重命名真正的 gcc.exe
    * -Off 只是把配置里的名字改回 gcc.exe
#>
param(
  [switch]$On,
  [switch]$Off,
  [switch]$Status,
  [string]$Ini = "$env:APPDATA\Dev-Cpp\devcpp.ini",
  [string]$BinDir = 'D:\Dev-Cpp\MinGW64\bin'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $Ini)) { throw "找不到 Dev-C++ 配置：$Ini" }
if (-not ($On -or $Off -or $Status)) { $Off = $true }   # 默认还原，最安全

$enc   = [Text.Encoding]::GetEncoding(936)   # devcpp.ini 是 GBK
$shimSrc = Join-Path $PSScriptRoot 'build\gcc-shim.exe'
$shimInBin = Join-Path $BinDir 'gcc-shim.exe'
$realGcc = Join-Path $BinDir 'gcc.exe'

function Read-Ini { [IO.File]::ReadAllText($Ini, $enc) -split "`r?`n" }
function Write-Ini($lines) { [IO.File]::WriteAllText($Ini, ($lines -join "`r`n"), $enc) }

function Get-CurrentValues {
  $lines = Read-Ini
  $section = ''
  $out = @()
  foreach ($l in $lines) {
    if ($l -match '^\[') { $section = $l.Trim(); continue }
    if ($section -match 'CompilerSets_\d' -and $l -match '^gcc\.exe=(.*)$') {
      $out += [pscustomobject]@{ Section = $section; Value = $Matches[1] }
    }
  }
  return $out
}

# ---------------- Status ----------------
if ($Status) {
  Write-Host ""
  Write-Host "  Dev-C++ 编译器配置" -ForegroundColor Cyan
  Write-Host "  配置文件 : $Ini" -ForegroundColor DarkGray
  Write-Host "  编译器目录: $BinDir" -ForegroundColor DarkGray
  Write-Host ""
  foreach ($v in Get-CurrentValues) {
    $mark = if ($v.Value -match 'shim') { "已接入 shim" } else { "原装" }
    $color = if ($v.Value -match 'shim') { 'Yellow' } else { 'Green' }
    Write-Host ("  {0,-18} gcc.exe={1,-16} [{2}]" -f $v.Section, $v.Value, $mark) -ForegroundColor $color
  }
  Write-Host ""
  Write-Host ("  真 gcc  : " + $(if (Test-Path $realGcc) { "存在 ✓" } else { "缺失 ✗" })) -ForegroundColor DarkGray
  Write-Host ("  shim 副本: " + $(if (Test-Path $shimInBin) { "已放入编译器目录" } else { "未放入" })) -ForegroundColor DarkGray
  Write-Host ""
  exit 0
}

# ---------------- 备份 ----------------
$bak = "$Ini.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
Copy-Item $Ini $bak
Write-Host "  已备份: $bak" -ForegroundColor DarkGray

$lines = Read-Ini
$section = ''
$changed = 0

if ($On) {
  if (-not (Test-Path $shimSrc)) { throw "找不到 $shimSrc（先编译 gcc-shim.c）" }
  if (-not (Test-Path $BinDir))   { throw "找不到编译器目录 $BinDir" }
  Copy-Item $shimSrc $shimInBin -Force
  Write-Host "  已复制 shim 到: $shimInBin" -ForegroundColor DarkGray

  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^\[') { $section = $lines[$i].Trim(); continue }
    if ($section -in @('[CompilerSets_0]', '[CompilerSets_1]') -and $lines[$i] -match '^gcc\.exe=') {
      Write-Host ("  [{0}] {1}  ->  gcc.exe=gcc-shim.exe" -f $section.Trim('[]'), $lines[$i]) -ForegroundColor Yellow
      $lines[$i] = 'gcc.exe=gcc-shim.exe'
      $changed++
    }
  }
  Write-Ini $lines
  Write-Host ""
  Write-Host "  接入完成（改了 $changed 处）。重启 Dev-C++ 生效。" -ForegroundColor Green
  Write-Host "  想还原：.\devcpp.ps1 -Off" -ForegroundColor DarkGray
}
else {
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^\[') { $section = $lines[$i].Trim(); continue }
    if ($section -match 'CompilerSets_\d' -and $lines[$i] -match '^gcc\.exe=' -and $lines[$i] -match 'shim') {
      Write-Host ("  [{0}] {1}  ->  gcc.exe=gcc.exe" -f $section.Trim('[]'), $lines[$i]) -ForegroundColor Yellow
      $lines[$i] = 'gcc.exe=gcc.exe'
      $changed++
    }
  }
  if ($changed -eq 0) {
    Write-Host "  当前已经是原装 gcc.exe，无需改动。" -ForegroundColor Green
    Remove-Item $bak -Force -ErrorAction SilentlyContinue
  } else {
    Write-Ini $lines
    Write-Host ""
    Write-Host "  已还原（改了 $changed 处）。重启 Dev-C++ 生效。" -ForegroundColor Green
  }
}

Write-Host ""
Write-Host ("  真 gcc: " + $(if (Test-Path $realGcc) { "存在 ✓ 未受影响" } else { "缺失 ✗ 请检查" })) -ForegroundColor DarkGray
