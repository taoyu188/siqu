/**
 * 编程题自动验证
 * ------------------------------------------------------------------
 * 对题库里每道 type==='code' 的题：
 *   1. 把 solution 写成 .c 文件
 *   2. 用真实 gcc 编译
 *   3. 按 tests 里的每组输入运行，比对期望输出
 *
 * 用法：
 *   node tools/verify-questions.js                验证全部编程题
 *   node tools/verify-questions.js --id g019      只验证一道
 *
 * 题目需要带 tests 字段，形如：
 *   "tests": [ { "input": "12 18\n", "expect": "6" } ]
 * 没有 tests 的题会被标记为"未覆盖"，不算失败但会提示。
 */
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const args = process.argv.slice(2);
const opt = (n, d) => { const i = args.indexOf(n); return i >= 0 && args[i + 1] ? args[i + 1] : d; };

const here = __dirname;
const appRoot = path.dirname(here);
const bankPath = opt('--bank', path.join(appRoot, 'core', 'questions.json'));
const onlyId = opt('--id', '');
const gcc = opt('--gcc', 'D:\\Dev-Cpp\\MinGW64\\bin\\gcc.exe');

const bank = JSON.parse(fs.readFileSync(bankPath, 'utf8').replace(/^\uFEFF/, ''));
const all = bank.questions || [];
const codeQs = all.filter((q) => (q.type || 'mcq') === 'code' && (!onlyId || q.id === onlyId));

if (!codeQs.length) {
  console.log(onlyId ? `找不到编程题 ${onlyId}` : '题库里没有编程题');
  process.exit(0);
}

const tmp = path.join(os.tmpdir(), 'siqu-verify-' + process.pid);
fs.mkdirSync(tmp, { recursive: true });

function norm(s) {
  return String(s == null ? '' : s).replace(/\r\n/g, '\n').replace(/[ \t]+/g, ' ').trim();
}

let pass = 0, fail = 0, uncovered = 0;
const failures = [];

for (const q of codeQs) {
  const cfile = path.join(tmp, `${q.id}.c`);
  const exe = path.join(tmp, `${q.id}.exe`);
  fs.writeFileSync(cfile, q.solution || '', 'utf8');

  const build = spawnSync(gcc, [cfile, '-o', exe], { encoding: 'utf8', stdio: 'pipe' });
  const buildOk = build.status === 0 && fs.existsSync(exe);
  if (!buildOk) {
    console.log(`  ✗ ${q.id} 编译失败`);
    (build.stderr || '').split('\n').slice(0, 3).forEach((l) => l.trim() && console.log(`      ${l}`));
    fail++;
    failures.push(q.id + ' 编译失败');
    continue;
  }

  const tests = Array.isArray(q.tests) ? q.tests : [];
  if (!tests.length) {
    console.log(`  ○ ${q.id} 编译通过，但没有 tests（未覆盖）`);
    uncovered++;
    continue;
  }

  let qPass = true;
  for (const [i, t] of tests.entries()) {
    const run = spawnSync(exe, [], { input: t.input || '', encoding: 'utf8', timeout: 5000 });
    const actual = norm(run.stdout);
    const expect = norm(t.expect);
    if (actual === expect) {
      pass++;
    } else {
      qPass = false;
      fail++;
      console.log(`  ✗ ${q.id} 用例${i + 1} 输入 ${JSON.stringify(t.input)}`);
      console.log(`      期望：${JSON.stringify(expect)}`);
      console.log(`      实际：${JSON.stringify(actual)}`);
      failures.push(`${q.id} 用例${i + 1}`);
    }
  }
  if (qPass) console.log(`  ✓ ${q.id} 通过 ${tests.length} 组用例`);
}

fs.rmSync(tmp, { recursive: true, force: true });

console.log('');
console.log(`  用例通过 ${pass} / 失败 ${fail} / 未覆盖 ${uncovered} 道题`);
if (failures.length) {
  console.log('');
  failures.forEach((f) => console.log(`   · ${f}`));
  process.exit(1);
}
process.exit(0);
