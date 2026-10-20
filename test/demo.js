/**
 * 祀 · 诊断能力演示（Node 版）
 * ------------------------------------------------------------------
 * 不依赖 PowerShell 执行策略，任何机器都能跑：
 *     node siqu\test\demo.js
 *
 * 流程：生成 10 个故意写错的 C 文件 → 真实编译 → 读取诊断 → 打印祀的反应
 */
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const here = __dirname;                       // siqu\test
const appRoot = path.dirname(here);           // siqu
const shim = path.join(appRoot, 'build', 'gcc-shim.exe');
const diag = path.join(appRoot, 'core', 'diagnose.js');
const work = path.join(here, 'demo');

if (!fs.existsSync(shim)) {
  console.error(`找不到编译器包装器：${shim}`);
  process.exit(1);
}
fs.mkdirSync(work, { recursive: true });

const log = path.join(work, 'build.log');
try { fs.unlinkSync(log); } catch (_) {}
const env = { ...process.env, SIQU_LOG: log };

const cases = {
  'd1_brace.c': `#include <stdio.h>
int main(void) {
    if (1) {
        printf("hi\\n");
    return 0;
}
`,
  'd2_redecl.c': `#include <stdio.h>
int main(void) {
    int a = 1;
    int a = 2;
    printf("%d\\n", a);
    return 0;
}
`,
  'd3_lvalue.c': `#include <stdio.h>
int main(void) {
    int a = 1;
    5 = a;
    printf("%d\\n", a);
    return 0;
}
`,
  'd4_subscript.c': `#include <stdio.h>
int main(void) {
    int a = 1;
    a[0] = 2;
    printf("%d\\n", a);
    return 0;
}
`,
  'd5_nodef.c': `#include <stdio.h>
int add(int x, int y);
int main(void) {
    printf("%d\\n", add(1, 2));
    return 0;
}
`,
  'd6_mian.c': `#include <stdio.h>
int mian(void) {
    printf("hello\\n");
    return 0;
}
`,
  'd7_uninit.c': `#include <stdio.h>
int main(void) {
    int sum;
    printf("%d\\n", sum);
    return 0;
}
`,
  'd8_ptr.c': `#include <stdio.h>
int main(void) {
    int n = 5;
    int *p = &n;
    char *q;
    q = p;
    printf("%p\\n", (void *)q);
    return 0;
}
`,
  'd9_noreturn.c': `#include <stdio.h>
int check(int x) {
    if (x > 0) return 1;
}
int main(void) {
    printf("%d\\n", check(3));
    return 0;
}
`,
  'd10_toofew.c': `#include <stdio.h>
int add(int a, int b) {
    return a + b;
}
int main(void) {
    printf("%d\\n", add(1));
    return 0;
}
`,
};

console.log('');
console.log('  祀 · 诊断能力演示（Node 版）');
console.log(`  编译器: ${shim}`);
console.log(`  日志  : ${log}`);
console.log('');

// ---- 1) 生成并编译 ----
const files = Object.keys(cases);
for (const name of files) {
  const src = path.join(work, name);
  fs.writeFileSync(src, cases[name], 'ascii');
  const exe = path.join(work, name.replace(/\.c$/, '.exe'));
  // stdio: 'ignore' —— 不捕获子进程输出。编译器的输出由 shim 自己写进日志，
  // 这里不需要管道（某些受限环境下管道会被拒绝）。
  const r = spawnSync(shim, [src, '-o', exe], { env, stdio: 'ignore' });
  console.log(`  编译 ${name.padEnd(16)} exit=${r.status}`);
}

// ---- 2) 诊断 ----
const outJson = path.join(os.tmpdir(), `siqu-demo-${process.pid}.json`);
spawnSync(process.execPath, [diag, '--file', log, '--all', '--json', '--out', outJson], {
  env, stdio: 'ignore',
});
if (!fs.existsSync(outJson)) {
  console.error('诊断没有产出结果文件');
  process.exit(1);
}

const results = JSON.parse(fs.readFileSync(outJson, 'utf8'));
const list = Array.isArray(results) ? results : [results];

console.log('');
console.log('  ══════════════════ 祀 的 反 应 ══════════════════');
console.log('');

let hit = 0;
list.forEach((r, i) => {
  const file = r.source ? path.basename(r.source) : '(未知)';
  const hits = r.hits || [];
  console.log(`  [${i + 1}] ${file}  (exit=${r.exit})`);
  if (hits.length) {
    hit++;
    console.log(`      「${hits[0].taunt}」`);
    console.log(`        → ${hits[0].title}`);
    console.log(`        修法: ${hits[0].fix}`);
    if (hits.length > 1) {
      console.log(`        （另有 ${hits.length - 1} 条相关：${hits.slice(1).map((h) => h.title).join('、')}）`);
    }
  } else if (r.ok) {
    console.log('        「编译过了，继续。」');
  } else {
    console.log('        「这个错我也没见过……」← 规则库缺口');
    (r.errorLines || []).slice(0, 2).forEach((l) => console.log(`        ${l.slice(0, 120)}`));
  }
  console.log('');
});

console.log(`  ══ 总结：${hit}/${list.length} 个样例被规则库识别 ══`);
console.log('');
