<#
  祀 · 诊断能力演示
  ------------------------------------------------------------------
  用 10 种不同的 C 错误，逐个验证规则库并打印祀的台词。

  用法（桌宠开着更好，会同步弹气泡）：
      powershell -ExecutionPolicy Bypass -File siqu\test\demo.ps1

  每一项都是一次真实的 gcc 调用，输出就是桌宠会看到的诊断结果。
#>
$ErrorActionPreference = 'Continue'

$here    = Split-Path -Parent $MyInvocation.MyCommand.Path      # siqu\test
$appRoot = Split-Path -Parent $here                             # siqu
$shim    = Join-Path $appRoot 'build\gcc-shim.exe'
$diag    = Join-Path $appRoot 'core\diagnose.js'
$work    = Join-Path $here 'demo'

if (-not (Test-Path $shim)) { throw "找不到 $shim" }
New-Item -ItemType Directory -Path $work -Force | Out-Null
$log = Join-Path $work 'build.log'
Remove-Item $log -Force -ErrorAction SilentlyContinue
$env:SIQU_LOG = $log

# ---------------- 10 个样例（故意写错） ----------------
$cases = [ordered]@{
  'd1_brace.c' = @'
#include <stdio.h>
int main(void) {
    if (1) {
        printf("hi\n");
    return 0;
}
'@
  'd2_redecl.c' = @'
#include <stdio.h>
int main(void) {
    int a = 1;
    int a = 2;
    printf("%d\n", a);
    return 0;
}
'@
  'd3_lvalue.c' = @'
#include <stdio.h>
int main(void) {
    int a = 1;
    5 = a;
    printf("%d\n", a);
    return 0;
}
'@
  'd4_subscript.c' = @'
#include <stdio.h>
int main(void) {
    int a = 1;
    a[0] = 2;
    printf("%d\n", a);
    return 0;
}
'@
  'd5_nodef.c' = @'
#include <stdio.h>
int add(int x, int y);
int main(void) {
    printf("%d\n", add(1, 2));
    return 0;
}
'@
  'd6_mian.c' = @'
#include <stdio.h>
int mian(void) {
    printf("hello\n");
    return 0;
}
'@
  'd7_uninit.c' = @'
#include <stdio.h>
int main(void) {
    int sum;
    printf("%d\n", sum);
    return 0;
}
'@
  'd8_ptr.c' = @'
#include <stdio.h>
int main(void) {
    int n = 5;
    int *p = &n;
    char *q;
    q = p;
    printf("%p\n", (void *)q);
    return 0;
}
'@
  'd9_noreturn.c' = @'
#include <stdio.h>
int check(int x) {
    if (x > 0) return 1;
}
int main(void) {
    printf("%d\n", check(3));
    return 0;
}
'@
  'd10_toofew.c' = @'
#include <stdio.h>
int add(int a, int b) {
    return a + b;
}
int main(void) {
    printf("%d\n", add(1));
    return 0;
}
'@
}

Write-Host ""
Write-Host "  祀 · 诊断能力演示" -ForegroundColor Cyan
Write-Host "  编译器: $shim" -ForegroundColor DarkGray
Write-Host "  日志  : $log" -ForegroundColor DarkGray
Write-Host ""

# ---------------- 逐个编译（模拟 Dev-C++ 一键编译+链接） ----------------
foreach ($name in $cases.Keys) {
  $src = Join-Path $work $name
  Set-Content -Path $src -Value $cases[$name] -Encoding ASCII
  $exe = Join-Path $work ([IO.Path]::GetFileNameWithoutExtension($name) + '.exe')
  $prev = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  & $shim $src -o $exe 2>&1 | Out-Null
  $code = $LASTEXITCODE
  $ErrorActionPreference = $prev
  Write-Host ("  编译 {0,-16} exit={1}" -f $name, $code) -ForegroundColor DarkGray
}

# ---------------- 诊断 ----------------
$tmpJson = Join-Path $env:TEMP "siqu-demo-$PID.json"
& node $diag --file $log --all --json --out $tmpJson 2>$null | Out-Null
if (-not (Test-Path $tmpJson)) { throw "诊断没有产出结果" }
$results = (Get-Content $tmpJson -Raw -Encoding UTF8) | ConvertFrom-Json

Write-Host ""
Write-Host "  ══════════════════ 祀 的 反 应 ══════════════════" -ForegroundColor Cyan
Write-Host ""

$i = 0
foreach ($r in @($results)) {
  $i++
  $file = if ($r.source) { Split-Path $r.source -Leaf } else { '(未知)' }
  $hits = @($r.hits)

  Write-Host ("  [{0}] {1}  (exit={2})" -f $i, $file, $r.exit) -ForegroundColor White
  if ($hits.Count -gt 0) {
    Write-Host ("      「{0}」" -f $hits[0].taunt) -ForegroundColor Yellow
    Write-Host ("        → {0}" -f $hits[0].title) -ForegroundColor Gray
    Write-Host ("        修法: {0}" -f $hits[0].fix) -ForegroundColor Green
    if ($hits.Count -gt 1) {
      Write-Host ("        （另有 {0} 条相关：{1}）" -f ($hits.Count - 1), (($hits[1..($hits.Count-1)] | ForEach-Object { $_.title }) -join '、')) -ForegroundColor DarkGray
    }
  } elseif ($r.ok) {
    Write-Host "        「编译过了，继续。」" -ForegroundColor Green
  } else {
    Write-Host "        「这个错我也没见过……」← 规则库缺口" -ForegroundColor Red
  }
  Write-Host ""
}

$hitCount = (@($results) | Where-Object { @($_.hits).Count -gt 0 }).Count
$total = @($results).Count
Write-Host ("  ══ 总结：{0}/{1} 个样例被规则库识别 ══" -f $hitCount, $total) -ForegroundColor Cyan
Write-Host ""
Write-Host "  未识别的样例说明规则库还缺这一条，可以把报错发给开发者补。" -ForegroundColor DarkGray
Write-Host ""
