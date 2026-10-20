#!/usr/bin/env node
/**
 * siqu 编译报错诊断
 * ------------------------------------------------------------------
 * 读取 gcc-shim.cmd 落下的日志，用规则库匹配，输出「原因 + 修法 + 一句台词」。
 * 规则命中就不花钱；没命中再决定要不要问模型（--llm）。
 *
 * 用法：
 *   node core\diagnose.js                 # 分析日志里最后一条编译记录
 *   node core\diagnose.js --json          # 输出 JSON（给桌宠 UI 用）
 *   node core\diagnose.js --all           # 分析全部记录
 *   node core\diagnose.js --file x.log    # 指定日志
 */
const fs = require('fs');
const os = require('os');
const path = require('path');

const args = process.argv.slice(2);
const flag = (n) => args.includes(n);
const opt = (n, d) => { const i = args.indexOf(n); return i >= 0 && args[i + 1] ? args[i + 1] : d; };

const LOG = opt('--file', path.join(os.homedir(), '.siqu', 'build.log'));
const RULES_PATH = path.join(__dirname, 'rules.json');
const AS_JSON = flag('--json');
const ALL = flag('--all');

if (!fs.existsSync(LOG)) {
  console.error(`没有日志：${LOG}\n先用 gcc-shim 编译一次（或设置 SIQU_LOG 指向你的日志）。`);
  process.exit(2);
}

const raw = fs.readFileSync(LOG, 'utf8');

// 记录头格式（兼容两种）：
//   === seq=123 exit=1 args=-c x.c              （旧版 .cmd shim）
//   === seq=123 exit=1 at=2026-10-19 20:41:26 args=-c x.c   （原生 shim）
const records = [];
let cur = null;
for (const line of raw.split(/\r?\n/)) {
  const m = line.match(/^=== seq=(-?\d+) exit=(-?\d+)(?: at=\S+ \S+)? args=(.*)$/);
  if (m) {
    if (cur) records.push(cur);
    cur = { seq: Number(m[1]), code: Number(m[2]), args: m[3], lines: [] };
  } else if (cur) {
    if (line === '---') continue;
    if (line.trim()) cur.lines.push(line);
  }
}
if (cur) records.push(cur);

if (!records.length) { console.error('日志里没有可解析的编译记录。'); process.exit(2); }
const targets = ALL ? records : [records[records.length - 1]];

const db = JSON.parse(fs.readFileSync(RULES_PATH, 'utf8').replace(/^\uFEFF/, ''));
const compiled = [...db.rules, ...(db.runtime || [])].map((r) => ({ ...r, re: new RegExp(r.pattern, 'i') }));

function analyze(rec) {
  const text = rec.lines.join('\n');
  const hits = [];
  for (const r of compiled) {
    const m = text.match(r.re);
    if (m) hits.push({ rule: r, match: m, sample: pickSample(rec.lines, r.re) });
  }
  // 去重：同一规则只保留一次
  const seen = new Set();
  const uniq = hits.filter((h) => (seen.has(h.rule.id) ? false : (seen.add(h.rule.id), true)));

  return {
    seq: rec.seq,
    exit: rec.code,
    source: guessSource(rec.args),
    ok: rec.code === 0,
    errorLines: rec.lines.filter((l) => /error|错误|undefined reference/i.test(l)).slice(0, 8),
    hits: uniq.map((h) => ({
      id: h.rule.id,
      title: h.rule.title,
      why: h.rule.why,
      fix: h.rule.fix,
      taunt: h.rule.taunt,
      sample: h.sample,
    })),
  };
}

function pickSample(lines, re) {
  const l = lines.find((x) => re.test(x));
  return l ? l.trim().slice(0, 200) : '';
}

function guessSource(a) {
  // 优先匹配引号包起来的路径（文件名可能带空格，比如 "Hello si.c"）
  const quoted = a.match(/"([^"]+\.(?:c|cpp|cc|cxx|C|CPP))"/);
  if (quoted) return quoted[1];
  const plain = a.match(/([^\s"]+\.(?:c|cpp|cc|cxx|C|CPP))\b/);
  return plain ? plain[1] : '';
}

const results = targets.map((rec, i) => ({ ...analyze(rec), ordinal: i + 1 }));

// ---------- 错题库 ----------
// 规则库没认出来的错误，记进 errorbook；下次再撞到同样的就能认出来。
const RECORD = flag('--record');
if (RECORD) {
  const { record } = require('./errorbook');
  results.forEach((r, i) => {
    if (!r.ok && r.hits.length === 0) {
      r.book = record({ lines: targets[i].lines, source: r.source, exit: r.exit });
    }
  });
}

// JSON 输出必须对编码免疫：
// PowerShell 5.1 用系统代码页（GBK）解码子进程 stdout，
// 直接输出 UTF-8 中文会被拆坏，甚至连引号都会被吃掉，
// 导致 ConvertFrom-Json 失败、桌宠默默不反应。
// 所以把非 ASCII 全部转成 \uXXXX 转义 —— 纯 ASCII 的 JSON。
function asciiJSON(value) {
  return JSON.stringify(value, null, 2)
    .replace(/[\u007f-\uffff]/g, (c) => '\\u' + c.charCodeAt(0).toString(16).padStart(4, '0'));
}

if (AS_JSON) {
  const text = asciiJSON(results.length === 1 ? results[0] : results);
  const outFile = opt('--out', null);
  if (outFile) fs.writeFileSync(outFile, text, 'utf8');
  else console.log(text);
  process.exit(0);
}

// ---------- 人读输出 ----------
const C = { g: '\x1b[32m', y: '\x1b[33m', r: '\x1b[31m', d: '\x1b[90m', b: '\x1b[36m', x: '\x1b[0m' };

for (const res of results) {
  console.log('');
  console.log(`${C.d}────────────────────────────────────────${C.x}`);
  console.log(`${C.d}#${res.ordinal}  源文件 ${res.source || '(未识别)'}  exit=${res.exit}${C.x}`);

  if (res.ok) {
    console.log(`${C.g}  这次编译通过了。${C.x}`);
    continue;
  }

  if (!res.hits.length) {
    console.log(`${C.y}  规则库没命中——这个错比较少见。${C.x}`);
    if (res.errorLines.length) {
      console.log(`${C.d}  原始报错：${C.x}`);
      res.errorLines.slice(0, 3).forEach((l) => console.log(`${C.d}    ${l.slice(0, 160)}${C.x}`));
    }
    continue;
  }

  const top = res.hits[0];
  console.log('');
  console.log(`${C.b}  祀：「${top.taunt}」${C.x}`);
  console.log('');
  res.hits.slice(0, 3).forEach((h, i) => {
    const tag = i === 0 ? `${C.r}●${C.x}` : `${C.y}○${C.x}`;
    console.log(`  ${tag} ${C.b}${h.title}${C.x}`);
    console.log(`     ${h.why}`);
    console.log(`     ${C.g}怎么改：${h.fix}${C.x}`);
    if (h.sample) console.log(`     ${C.d}${h.sample}${C.x}`);
    console.log('');
  });
}
