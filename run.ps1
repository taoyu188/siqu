<#
  启动 siqu 桌宠（开发模式）
  用法：
    powershell -File siqu\run.ps1          # 正常启动
    powershell -File siqu\run.ps1 -Dev     # 带 DevTools
#>
param([switch]$Dev)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$electron = Join-Path $root 'node_modules\electron\dist\electron.exe'

if (-not (Test-Path $electron)) {
  throw "Electron 还没装好：$electron 不存在。先跑 npm install 并执行 node_modules\electron\install.js"
}

if ($Dev) { $env:SIQU_DEV = '1' }

$extra = @()
if ($env:SIQU_NO_SANDBOX -eq '1') {
  # 仅在"受限 job object"的开发/沙箱环境里需要（比如这个 agent 的执行环境）。
  # 正常双击桌面快捷方式启动时不需要这个参数。
  $extra += '--no-sandbox'
}

& $electron $extra $root
