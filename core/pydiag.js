/**
 * Python 报错诊断
 * ------------------------------------------------------------------
 * 从 python.log 里取出最近一次运行的 Traceback，解析成结构化的结果。
 *
 * 用法：
 *   node core/pydiag.js                     诊断最近一次运行（人读）
 *   node core/pydiag.js --json --out x.json 给界面/桌宠用
 *   node core/pydiag.js --file <日志>       指定日志
 *   node core/pydiag.js --tail 3            看最近 3 次运行
 *
 * 输出字段：ok / type / message / file / line / source / rule / taunt
 */
const fs = require('fs');
const os = require('os');
const path = require('path');

const appRoot = path.dirname(__dirname);
const rulesPath = path.join(appRoot, 'core', 'py-rules.json');

function homeDir() { return process.env.SIQU_HOME || path.join(os.homedir(), '.siqu'); }
function defaultLog() { return path.join(homeDir(), 'python.log'); }

const args = process.argv.slice(2);
const has = (f) => args.includes(f);
const opt = (n, d) => { const i = args.indexOf(n); return i >= 0 && args[i + 1] ? args[i + 1] : d; };

function loadRules() {
  try { return JSON.parse(fs.readFileSync(rulesPath, 'utf8').replace(/^\uFEFF/, '')); }
  catch { return { rules: [], generic: {} }; }
}

/** 按 RUN 标记切分日志，取最近的若干次 */
function splitRuns(text) {
  const parts = text.split(/^=== RUN .*===$/m).filter((s) => s.trim());
  return parts.map((s) => s.replace(/^=== EXIT .*===$/gm, ''));
}

const EXC_RE = /^([A-Za-z_][\w.]*(?:Error|Exception|Warning|Interrupt|Exit|Iteration|Overflow))(?::\s*(.*))?$/;
const FILE_RE = /^\s+File "([^"]+)", line (\d+)(?:, in (.+))?$/;

/** 解析一段 traceback */
function parseRun(chunk) {
  const lines = chunk.split(/\r?\n/);
  let excType = null, excMsg = '', excIndex = -1;

  for (let i = lines.length - 1; i >= 0; i--) {
    const m = lines[i].trim().match(EXC_RE);
    if (m) { excType = m[1]; excMsg = (m[2] || '').trim(); excIndex = i; break; }
  }
  if (!excType) return null;

  // 找最后一个 File 行（真正的出错位置）
  let frame = null;
  for (let i = excIndex - 1; i >= 0; i--) {
    const fm = lines[i].match(FILE_RE);
    if (fm) {
      // 源码行在 File 行的下一行（缩进更深的那行）
      let src = '';
      for (let j = i + 1; j < excIndex; j++) {
        if (lines[j].trim()) { src = lines[j].trim(); break; }
      }
      frame = { file: fm[1], line: Number(fm[2]), func: (fm[3] || '').trim(), source: src };
      break;
    }
  }

  return {
    ok: false,
    type: excType,
    message: excMsg,
    file: frame ? frame.file : null,
    line: frame ? frame.line : null,
    func: frame ? frame.func : null,
    source: frame ? frame.source : '',
    fullText: lines.slice(Math.max(0, excIndex - 12), excIndex + 1).join('\n'),
  };
}

/** 匹配规则 */
function matchRule(info, db) {
  const text = `${info.type}: ${info.message}`;
  for (const r of db.rules || []) {
    let re;
    try { re = new RegExp(r.pattern, 'i'); } catch { continue; }
    const m = text.match(re) || info.fullText.match(re);
    if (m) {
      const out = { id: r.id, title: r.title, why: r.why, fix: r.fix, taunt: r.taunt };
      if (m.length > 1) out.captures = m.slice(1).filter((x) => x !== undefined);
      return out;
    }
  }
  const g = db.generic || {};
  return { id: 'py-generic', title: g.title || '未定义的错误', why: g.why || '', fix: g.fix || '', taunt: g.taunt || '……' };
}

function diagnose(logPath, which = 1) {
  if (!fs.existsSync(logPath)) {
    return { ok: null, reason: 'no-log', message: `没有日志：${logPath}`, hint: '用 node core/pyrun.js 跑一次脚本就会生成' };
  }
  const text = fs.readFileSync(logPath, 'utf8');
  const runs = splitRuns(text);
  if (!runs.length) return { ok: null, reason: 'empty', message: '日志里还没有运行记录' };

  const pick = runs[Math.max(0, runs.length - which)];
  const info = parseRun(pick);
  if (!info) {
    return { ok: true, reason: 'no-error', message: '这次运行没有报错' };
  }
  const db = loadRules();
  info.rule = matchRule(info, db);
  return info;
}

const logPath = opt('--file', defaultLog());
const tail = Number(opt('--tail', '1')) || 1;

if (has('--json')) {
  const r = diagnose(logPath, tail);
  const outPath = opt('--out', '');
  const s = JSON.stringify(r, null, 2);
  if (outPath) { fs.writeFileSync(outPath, s, 'utf8'); console.log('已写入 ' + outPath); }
  else console.log(s);
  process.exit(0);
}

const r = diagnose(logPath, tail);
console.log('');
if (r.ok === true) {
  console.log('  这次运行没有报错。');
} else if (r.ok === null) {
  console.log(`  ${r.message}`);
  if (r.hint) console.log(`  ${r.hint}`);
} else {
  console.log(`  祀：「${r.rule.taunt}」`);
  console.log('');
  console.log(`  ● ${r.rule.title}`);
  console.log(`     ${r.rule.why}`);
  console.log(`     怎么改：${r.rule.fix}`);
  console.log('');
  if (r.file) console.log(`     位置：${r.file}:${r.line}${r.func ? '  (在 ' + r.func + ')' : ''}`);
  if (r.source) console.log(`     代码：${r.source}`);
  console.log(`     报错：${r.type}${r.message ? ': ' + r.message : ''}`);
}
console.log('');
