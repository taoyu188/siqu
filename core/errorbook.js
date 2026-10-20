/**
 * 祀 · 错题库（errorbook）
 * ==================================================================
 * 作用：规则库没认出来的错误，自动记下来。
 *   - 第一次遇到 → 记一条，她告诉你「记下来了」
 *   - 再次遇到   → 她认得出来：「又是这个。第 3 次了。」
 *   - 之后补了规则 → 自动标记为「已认识」
 *
 * 存储：%USERPROFILE%\.siqu\errorbook.json
 *
 * CLI：
 *   node core/errorbook.js --list        看错题库（按出现次数排序）
 *   node core/errorbook.js --json        机器可读
 *   node core/errorbook.js --clear       清空
 *   node core/errorbook.js --path        只打印文件路径
 */
const fs = require('fs');
const os = require('os');
const path = require('path');

// 允许用 SIQU_HOME 覆盖（测试/便携用）；默认 %USERPROFILE%\.siqu
const HOME = process.env.SIQU_HOME || path.join(os.homedir(), '.siqu');
const FILE = path.join(HOME, 'errorbook.json');
const MAX_ENTRIES = 300;

function emptyBook() {
  return { version: 1, entries: {} };
}

function load() {
  try {
    const raw = fs.readFileSync(FILE, 'utf8').replace(/^\uFEFF/, '');
    const book = JSON.parse(raw);
    if (!book.entries) book.entries = {};
    return book;
  } catch (_) {
    return emptyBook();
  }
}

function save(book) {
  try {
    fs.mkdirSync(HOME, { recursive: true });
    fs.writeFileSync(FILE, JSON.stringify(book, null, 2), 'utf8');
    return true;
  } catch (_) {
    return false;
  }
}

/**
 * 把一条编译器报错压成"指纹"：
 * 去掉路径、行号列号、具体数字，只留下错误本身的形状。
 * 这样同一个错误在不同文件、不同行，也能认出来。
 */
function fingerprint(lines) {
  const first = lines.find((l) => /error|warning|undefined reference/i.test(l)) || lines[0] || '';
  return first
    .replace(/^[A-Za-z]:\\[^:]*?:\d+:\d+:\s*/, '')   // C:\path\x.c:12:3:
    .replace(/^[^:]*?:\d+:\d+:\s*/, '')               // x.c:12:3:
    .replace(/\b\d+\b/g, 'N')                        // 数字归一
    .replace(/\s+/g, ' ')
    .trim()
    .toLowerCase()
    .slice(0, 300);
}

function prune(book) {
  const keys = Object.keys(book.entries);
  if (keys.length <= MAX_ENTRIES) return;
  const sorted = keys
    .map((k) => [k, book.entries[k]])
    .sort((a, b) => (a[1].lastSeen || '') < (b[1].lastSeen || '')); // 最久没出现的先删
  const drop = sorted.slice(0, keys.length - MAX_ENTRIES);
  for (const [k] of drop) delete book.entries[k];
}

/**
 * 记录一次"没被规则认出来"的错误。
 * 返回 { isRepeat, count, firstSeen, fingerprint }
 */
function record({ lines, source, exit }) {
  const book = load();
  const fp = fingerprint(lines || []);
  if (!fp) return { isRepeat: false, count: 0, fingerprint: '' };

  const now = new Date().toISOString();
  const cur = book.entries[fp];
  if (cur) {
    cur.count = (cur.count || 1) + 1;
    cur.lastSeen = now;
    if (source && !(cur.files || []).includes(path.basename(source))) {
      cur.files = (cur.files || []).concat(path.basename(source)).slice(-10);
    }
    const saved = save(book);
    return { isRepeat: true, count: cur.count, firstSeen: cur.firstSeen, fingerprint: fp, short: cur.short || '', saved: saved };
  }

  const firstErr = (lines || []).find((l) => /error/i.test(l))
    || (lines || []).find((l) => l && l.trim())
    || '';

  // 气泡里显示用：去掉前面那一长串路径和行号，只留错误本身
  const short = firstErr.replace(/^.*?:\d+:\d+:\s*/, '').trim().slice(0, 160);

  book.entries[fp] = {
    sample: firstErr.trim().slice(0, 200),
    short: short,
    raw: (lines || []).slice(0, 6),
    count: 1,
    firstSeen: now,
    lastSeen: now,
    exit: exit,
    files: source ? [path.basename(source)] : [],
    resolved: false,
  };
  prune(book);
  const saved = save(book);
  return { isRepeat: false, count: 1, firstSeen: now, fingerprint: fp, short: short, saved: saved };
}

/** 某条规则补上之后，把这些指纹标记为"已认识" */
function markResolved(fingerprints) {
  const book = load();
  let n = 0;
  for (const fp of fingerprints || []) {
    if (book.entries[fp] && !book.entries[fp].resolved) {
      book.entries[fp].resolved = true;
      n++;
    }
  }
  if (n) save(book);
  return n;
}

function stats() {
  const book = load();
  const all = Object.entries(book.entries).map(([fp, v]) => ({ fingerprint: fp, ...v }));
  const pending = all.filter((e) => !e.resolved);
  return {
    total: all.length,
    pending: pending.length,
    resolved: all.length - pending.length,
    top: pending.sort((a, b) => (b.count || 0) - (a.count || 0)).slice(0, 20),
  };
}

module.exports = { record, load, save, stats, markResolved, fingerprint, FILE };

// ---------------- CLI ----------------
if (require.main === module) {
  const args = process.argv.slice(2);
  const has = (f) => args.includes(f);

  if (has('--path')) {
    console.log(FILE);
    process.exit(0);
  }
  if (has('--clear')) {
    save(emptyBook());
    console.log('错题库已清空');
    process.exit(0);
  }

  const s = stats();
  if (has('--json')) {
    console.log(JSON.stringify(s, null, 2));
    process.exit(0);
  }

  console.log('');
  console.log(`  错题库：共 ${s.total} 条（待补规则 ${s.pending} 条，已认识 ${s.resolved} 条）`);
  console.log(`  文件：${FILE}`);
  console.log('');
  if (!s.top.length) {
    console.log('  还是空的。等你撞到规则库没覆盖的错误，就会自动记进来。');
  } else {
    s.top.forEach((e, i) => {
      const short = e.short || (e.sample || '').replace(/^.*?:\d+:\d+:\s*/, '');
      console.log(`  ${String(i + 1).padStart(2)}. [出现 ${e.count} 次] ${short}`);
      if (e.files && e.files.length) console.log(`      文件: ${e.files.join(', ')}`);
      console.log(`      最后: ${e.lastSeen}`);
    });
  }
  console.log('');
}
