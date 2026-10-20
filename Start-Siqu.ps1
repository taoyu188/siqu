<#
  一键启动 siqu 桌宠（WPF 版）
  ------------------------------------------------------------------
  桌面快捷方式指向这个脚本。

  为什么不用 Electron：
    这台机器上 Electron/Chromium 起不来（进程在 app.whenReady() 之前就崩），
    而 WPF 是纯 .NET，没有 Chromium 那套依赖，启动也更快更省内存。

  失败时会弹窗并给出日志最后几行，不会再"静默失败"。
#>
$ErrorActionPreference = 'Stop'

# 支持两种布局：脚本在仓库根目录（新）或上一层（旧），都找得到 Pet.ps1
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$petPs1 = Join-Path $root 'wpf\Pet.ps1'
# ---- 依赖检查：没有 Node.js 就早点提示，别让人看到一堆报错 ----
$nodeCmd = Get-Command node -ErrorAction SilentlyContinue
if (-not $nodeCmd) {
  Show-Error '祀 · 缺少 Node.js' @"
这个桌宠的核心功能（编译诊断、人格、每日三题、日程）需要 Node.js。

请先安装 Node.js 18 或更新版本：
  https://nodejs.org/

装好后重新运行本脚本。
"@
  exit 1
}

if (-not (Test-Path $petPs1)) { $petPs1 = Join-Path $root 'siqu\wpf\Pet.ps1' }
# ---- 依赖检查：没有 Node.js 就早点提示，别让人看到一堆报错 ----
$nodeCmd = Get-Command node -ErrorAction SilentlyContinue
if (-not $nodeCmd) {
  Show-Error '祀 · 缺少 Node.js' @"
这个桌宠的核心功能（编译诊断、人格、每日三题、日程）需要 Node.js。

请先安装 Node.js 18 或更新版本：
  https://nodejs.org/

装好后重新运行本脚本。
"@
  exit 1
}

if (-not (Test-Path $petPs1)) { $root = Split-Path -Parent $root; $petPs1 = Join-Path $root 'siqu\wpf\Pet.ps1' }

$siquHome  = Join-Path $env:USERPROFILE '.siqu'
$aliveFile = Join-Path $siquHome 'pet-alive.json'
$petLog    = Join-Path $siquHome 'pet.log'
$errLog    = Join-Path $siquHome 'pet.stderr.log'

function Show-Error($title, $msg) {
  Add-Type -AssemblyName System.Windows.Forms
  [System.Windows.Forms.MessageBox]::Show($msg, $title, 'OK', 'Error') | Out-Null
}

# ---- 依赖检查：没有 Node.js 就早点提示，别让人看到一堆报错 ----
$nodeCmd = Get-Command node -ErrorAction SilentlyContinue
if (-not $nodeCmd) {
  Show-Error '祀 · 缺少 Node.js' @"
这个桌宠的核心功能（编译诊断、人格、每日三题、日程）需要 Node.js。

请先安装 Node.js 18 或更新版本：
  https://nodejs.org/

装好后重新运行本脚本。
"@
  exit 1
}

if (-not (Test-Path $petPs1)) {
  Show-Error '祀 · 启动失败' "找不到主脚本：`n$petPs1"
  exit 1
}
if (-not (Test-Path $siquHome)) { New-Item -ItemType Directory -Path $siquHome -Force | Out-Null }

# 已经在跑就别重复开
if (Test-Path $aliveFile) {
  try {
    $info = Get-Content $aliveFile -Raw | ConvertFrom-Json
    if ($info.pid -and (Get-Process -Id $info.pid -ErrorAction SilentlyContinue)) {
      Show-Error '祀 · 已经在运行' "桌宠已经开着啦（PID $($info.pid)）。`n`n如果看不到窗口，在任务管理器里结束 PowerShell 进程再试。"
      exit 0
    }
  } catch { }
  Remove-Item $aliveFile -Force -ErrorAction SilentlyContinue
}

Remove-Item $errLog -Force -ErrorAction SilentlyContinue

$ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
try {
  Start-Process -FilePath $ps `
    -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$petPs1`"") `
    -WorkingDirectory $root `
    -RedirectStandardError $errLog | Out-Null
} catch {
  Show-Error '祀 · 启动失败' "无法启动：`n$($_.Exception.Message)"
  exit 1
}

# 等窗口自己报告"已显示"
$deadline = (Get-Date).AddSeconds(20)
$ok = $false
while ((Get-Date) -lt $deadline) {
  Start-Sleep -Milliseconds 400
  if (Test-Path $aliveFile) {
    try {
      $info = Get-Content $aliveFile -Raw | ConvertFrom-Json
      if ($info.stage -eq 'shown') { $ok = $true; break }
    } catch { }
  }
}
if ($ok) { exit 0 }

# ---- 失败：收集证据 ----
$tail = ''
foreach ($f in @($petLog, $errLog)) {
  if (Test-Path $f) {
    $content = Get-Content $f -Raw -ErrorAction SilentlyContinue
    if ($content) {
      $lines = ($content -split "`r?`n" | Where-Object { $_.Trim() }) | Select-Object -Last 10
      $tail += "`n--- $([IO.Path]::GetFileName($f)) ---`n" + ($lines -join "`n")
    }
  }
}
if (-not $tail) { $tail = "`n（没有任何日志，脚本可能根本没跑起来）" }

Show-Error '祀 · 启动失败' @"
桌宠窗口没能显示。

日志：
  $petLog
  $errLog

最后几行：
$tail

把这段内容发给开发者。
"@
exit 1
