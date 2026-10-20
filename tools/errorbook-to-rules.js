/**
 * 错题库 → 规则库 转化工具
 * ------------------------------------------------------------------
 * 错题库（errorbook）记的是"规则没认出来的错误"。这个工具负责：
 *   1. 列出还没被规则覆盖的错误（按出现次数排序）
 *   2. 检查新加的规则是否已经把某些错误覆盖了 → 自动标记为"已认识"
 *   3. 为未覆盖的错误生成规则草稿（skeleton），人工补上标题/原因/修法/台词后即可启用
 *
 * 用法：
 *   node tools/errorbook-to-rules.js --list
 *       看有哪些待转化，以及是否已被现有规则覆盖
 *
 *   node tools/errorbook-to-rules.js --draft
 *       生成 core/rules-draft.json（草稿，不会自动生效）
 *
 *   node tools/errorbook-to-rules.js --sync
 *       重新检查覆盖情况，把"现在已被规则覆盖"的条目标记为已认识
 *
 *   node tools/errorbook-to-rules.js --add <指纹序号> --id my-rule \
 *        --title "标题" --why "原因" --fix "修法" --taunt "台词"
 *       直接把某条草稿变成正式规则，并标记该错误为已认识
 */
const fs = require('fs');
const path = require('path');

const here = __dirname;
const appRoot = path.dirname(here);
const rulesPath = path.join(appRoot, 'core', 'rules.json');
const draftPath = path.join(appRoot, 'core', 'rules-draft.json');

// 复用 errorbook 的实现（同一个 SIQU_HOME 规则）
const errorbook = require(path.join(appRoot, 'core', 'errorbook.js'));

const args = process.argv.slice(2);
const has = (f) => args.includes(f);
const opt = (n, d) => { const i = args.indexOf(n); return i >= 0 && args[i + 1] ? args[i + 1] : d; };

function loadRules() {
  return JSON.parse(fs.readFileSync(rulesPath, 'utf8').replace(/^\uFEFF/, ''));
}
function saveRules(db) {
  fs.writeFileSync(rulesPath, JSON.stringify(db, null, 2), 'utf8');
}

function compileRules(db) {
  return (db.rules || []).map((r) => {
    try { return { ...r, re: new RegExp(r.pattern, 'i') }; }
    catch (_) { return null; }
  }).filter(Boolean);
}

/** 某条错误是否已被现有规则覆盖 */
function coveredBy(entry, compiled) {
  const text = [entry.sample, ...(entry.raw || [])].filter(Boolean).join('\n');
  if (!text) return null;
  for (const r of compiled) {
    if (r.re.test(text)) return r;
  }
  return null;
}

/** 从错误样本生成一个保守的正则（去掉路径/行号/数字） */
function patternFromSample(sample) {
  let s = String(sample || '')
    .replace(/^.*?:\d+:\d+:\s*/, '')       // 去掉 path:line:col:
    .replace(/^error:\s*/i, '')            // 去掉开头的 error:
    .replace(/[-/\\^$*+?.()|[\]{}]/g, '\\$&')  // 转义正则元字符
    .replace(/\b\d+\b/g, '\\d+')           // 数字泛化
    .trim();
  if (!s) return 'PLACEHOLDER_PATTERN';
  return s;
}

function pendingEntries() {
  const book = errorbook.load();
  const compiled = compileRules(loadRules());
  const out = [];
  for (const [fp, v] of Object.entries(book.entries || {})) {
    if (v.resolved) continue;
    const hit = coveredBy(v, compiled);
    out.push({
      fingerprint: fp,
      count: v.count || 1,
      sample: v.sample || '',
      short: v.short || '',
      files: v.files || [],
      lastSeen: v.lastSeen || '',
      coveredBy: hit ? hit.id : null,
    });
  }
  out.sort((a, b) => (b.count || 0) - (a.count || 0));
  return out;
}

// ---------------- 子命令 ----------------
if (has('--list') || (!has('--draft') && !has('--sync') && !has('--add'))) {
  const list = pendingEntries();
  if (!list.length) {
    console.log('\n  错题库里没有待转化的条目。\n');
    process.exit(0);
  }
  console.log('');
  console.log(`  待处理 ${list.length} 条：`);
  console.log('');
  list.forEach((e, i) => {
    console.log(`  [${i + 1}] 出现 ${e.count} 次   ${e.short || e.sample.slice(0, 60)}`);
    console.log(`      样本：${e.sample.slice(0, 100)}`);
    if (e.files.length) console.log(`      文件：${e.files.join(', ')}`);
    if (e.coveredBy) console.log(`      ✓ 已被规则 ${e.coveredBy} 覆盖（可用 --sync 标记为已认识）`);
    else console.log(`      ✗ 还没有规则覆盖它`);
    console.log('');
  });
  process.exit(0);
}

if (has('--sync')) {
  const book = errorbook.load();
  const compiled = compileRules(loadRules());
  const resolved = [];
  for (const [fp, v] of Object.entries(book.entries || {})) {
    if (v.resolved) continue;
    const hit = coveredBy(v, compiled);
    if (hit) { v.resolved = true; resolved.push({ fp, rule: hit.id }); }
  }
  if (resolved.length) {
    errorbook.save(book);
    console.log(`\n  已标记 ${resolved.length} 条为「已认识」：`);
    resolved.forEach((r) => console.log(`   · ${r.fp.slice(0, 50)}  ←  ${r.rule}`));
  } else {
    console.log('\n  没有新的条目被现有规则覆盖。');
  }
  console.log('');
  process.exit(0);
}

if (has('--draft')) {
  const list = pendingEntries().filter((e) => !e.coveredBy);
  if (!list.length) {
    console.log('\n  没有需要起草的条目（都已覆盖或为空）。\n');
    process.exit(0);
  }
  const drafts = list.map((e, i) => ({
    id: `auto-${String(i + 1).padStart(2, '0')}`,
    pattern: patternFromSample(e.sample),
    title: '（待填）这个错误是什么',
    why: '（待填）为什么会发生',
    fix: '（待填）怎么改',
    taunt: '（待填）她的一句话',
    _from: { fingerprint: e.fingerprint, count: e.count, sample: e.sample },
  }));
  fs.writeFileSync(draftPath, JSON.stringify({ _comment: '规则草稿：补完 title/why/fix/taunt 后用 --add 启用', rules: drafts }, null, 2), 'utf8');
  console.log(`\n  已生成 ${drafts.length} 条草稿：${draftPath}`);
  console.log('  补完字段后，用 --add 启用其中一条。\n');
  process.exit(0);
}

if (has('--add')) {
  const idx = Number(opt('--add', '0'));
  const id = opt('--id', '');
  const title = opt('--title', '');
  const why = opt('--why', '');
  const fix = opt('--fix', '');
  const taunt = opt('--taunt', '');

  if (!fs.existsSync(draftPath)) { console.error('没有草稿文件，先跑 --draft'); process.exit(2); }
  const draft = JSON.parse(fs.readFileSync(draftPath, 'utf8').replace(/^\uFEFF/, ''));
  const list = pendingEntries().filter((e) => !e.coveredBy);
  const target = list[idx - 1];
  if (!target) { console.error(`序号 ${idx} 不存在（当前 ${list.length} 条）`); process.exit(2); }
  if (!id || !title) { console.error('至少需要 --id 和 --title'); process.exit(2); }

  const db = loadRules();
  if ((db.rules || []).some((r) => r.id === id)) {
    console.error(`规则 id 已存在：${id}`);
    process.exit(2);
  }

  const rule = {
    id,
    pattern: patternFromSample(target.sample),
    title,
    why: why || title,
    fix: fix || '（未填写）',
    taunt: taunt || '……又来了。',
  };
  db.rules.push(rule);
  saveRules(db);

  // 标记为已认识
  const book = errorbook.load();
  if (book.entries[target.fingerprint]) {
    book.entries[target.fingerprint].resolved = true;
    errorbook.save(book);
  }

  console.log(`\n  已添加规则 ${id}，并标记该错误为已认识。`);
  console.log(`  规则数：${db.rules.length}`);
  console.log(`  提示：跑一次 node core/diagnose.js --file <日志> 验证能命中。\n`);
  process.exit(0);
}
