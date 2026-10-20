/**
 * 祀 · 每日三题（调度 + 记忆 + 简化间隔重复）
 * ==================================================================
 * 题库：core/questions.json
 * 状态：%USERPROFILE%\.siqu\questions-state.json
 *
 * CLI：
 *   node core/daily.js --today                今天的 3 道题（人读）
 *   node core/daily.js --today --json --out f 给面板用
 *   node core/daily.js --answer q003 --right   答对
 *   node core/daily.js --answer q003 --wrong   答错
 *   node core/daily.js --stats                 统计
 *   node core/daily.js --reset                 清空记录
 *
 * 间隔重复（简化版 SM-2）：
 *   答对 → 连对次数 +1，下次复习 = 今天 + (1,2,4,7,15) 天
 *   答错 → 连对清零，明天再来
 *   每道题按"是否到期"优先被抽中，没到期的不再出现
 */
const fs = require('fs');
const os = require('os');
const path = require('path');

const HOME = process.env.SIQU_HOME || path.join(os.homedir(), '.siqu');
const STATE_FILE = path.join(HOME, 'questions-state.json');
const BANK_FILE = path.join(__dirname, 'questions.json');

const PER_DAY = 3;

function today() {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}
function addDays(iso, n) {
  const d = new Date(iso + 'T00:00:00');
  d.setDate(d.getDate() + n);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}
function dayDiff(a, b) {
  return Math.round((new Date(a + 'T00:00:00') - new Date(b + 'T00:00:00')) / 86400000);
}

function loadBank() {
  const raw = fs.readFileSync(BANK_FILE, 'utf8').replace(/^\uFEFF/, '');
  return JSON.parse(raw).questions || [];
}

function loadState() {
  try {
    const raw = fs.readFileSync(STATE_FILE, 'utf8').replace(/^\uFEFF/, '');
    const s = JSON.parse(raw);
    if (!s.cards) s.cards = {};
    if (!s.today) s.today = null;
    return s;
  } catch (_) {
    return { version: 1, cards: {}, today: null, firstSeen: today() };
  }
}
function saveState(s) {
  try {
    fs.mkdirSync(HOME, { recursive: true });
    fs.writeFileSync(STATE_FILE, JSON.stringify(s, null, 2), 'utf8');
    return true;
  } catch (_) { return false; }
}

// 选题：优先到期/没做过的，其次随机；同一天固定不变
function pickToday(bank, state) {
  const d = today();
  if (state.today && state.today.date === d && Array.isArray(state.today.ids) && state.today.ids.length) {
    return state.today.ids;
  }

  const scored = bank.map((q) => {
    const c = state.cards[q.id] || {};
    const seen = !!c.lastAt;
    const due = !seen || !c.nextAt || dayDiff(d, c.nextAt) >= 0;
    return { id: q.id, due, seen, lastAt: c.lastAt || '', streak: c.streak || 0 };
  });

  // 到期池：1) 没做过的优先 2) 最久没做的优先
  const pool = scored.filter((x) => x.due);
  pool.sort((a, b) => {
    if (a.seen !== b.seen) return a.seen ? 1 : -1;
    return (a.lastAt || '') < (b.lastAt || '') ? -1 : 1;
  });

  // 用日期做种子的确定性洗牌：同一天结果固定，不同天不一样
  const seedBase = d.split('-').join('');
  let seed = 0;
  for (const ch of seedBase) seed = (seed * 31 + ch.charCodeAt(0)) >>> 0;
  const rnd = () => { seed = (seed * 1103515245 + 12345) >>> 0; return seed / 4294967296; };
  const shuffled = pool.slice();
  for (let i = shuffled.length - 1; i > 0; i--) {
    const j = Math.floor(rnd() * (i + 1));
    [shuffled[i], shuffled[j]] = [shuffled[j], shuffled[i]];
  }

  // 每天尽量保证：1 道编程题 + 2 道选择题
  const isCode = (id) => {
    const q = bank.find((x) => x.id === id);
    return q && (q.type || 'mcq') === 'code';
  };
  const ids = [];
  const codeFirst = shuffled.find((x) => isCode(x.id));
  if (codeFirst) ids.push(codeFirst.id);
  for (const x of shuffled) {
    if (ids.length >= PER_DAY) break;
    if (ids.includes(x.id)) continue;
    if (isCode(x.id)) continue;           // 编程题只取一道
    ids.push(x.id);
  }
  // 不够就补（含编程题）
  for (const x of shuffled) {
    if (ids.length >= PER_DAY) break;
    if (!ids.includes(x.id)) ids.push(x.id);
  }

  state.today = { date: d, ids, answered: {} };
  saveState(state);
  return ids;
}

function getToday() {
  const bank = loadBank();
  const state = loadState();
  const ids = pickToday(bank, state);
  const questions = ids.map((id) => {
    const q = bank.find((x) => x.id === id);
    if (!q) return null;
    const answered = state.today.answered?.[id] || null;
    const base = {
      id: q.id,
      type: q.type || 'mcq',
      topic: q.topic,
      explain: q.explain,
      answered,   // null | 'right' | 'wrong'
    };
    if ((q.type || 'mcq') === 'code') {
      return {
        ...base,
        title: q.title || '',
        statement: q.statement || '',
        io: q.io || '',
        solution: q.solution || '',
      };
    }
    return { ...base, q: q.q, options: q.options, answer: q.answer };
  }).filter(Boolean);

  const done = questions.filter((x) => x.answered).length;
  return { date: today(), questions, done, total: questions.length };
}

function answer(id, correct) {
  const bank = loadBank();
  const state = loadState();
  const d = today();
  if (!state.today || state.today.date !== d) pickToday(bank, state);

  const c = state.cards[id] || { streak: 0, right: 0, wrong: 0 };
  if (correct) {
    c.streak = (c.streak || 0) + 1;
    c.right = (c.right || 0) + 1;
    const iv = [1, 2, 4, 7, 15][Math.min(c.streak - 1, 4)];
    c.nextAt = addDays(d, iv);
    c.interval = iv;
  } else {
    c.streak = 0;
    c.wrong = (c.wrong || 0) + 1;
    c.nextAt = addDays(d, 1);
    c.interval = 1;
  }
  c.lastAt = d;
  state.cards[id] = c;
  state.today.answered = state.today.answered || {};
  state.today.answered[id] = correct ? 'right' : 'wrong';
  const saved = saveState(state);

  return {
    id, correct,
    streak: c.streak, nextAt: c.nextAt, interval: c.interval,
    right: c.right, wrong: c.wrong, saved,
  };
}

function stats() {
  const bank = loadBank();
  const state = loadState();
  const d = today();
  const cards = Object.entries(state.cards);
  const seen = cards.length;
  const due = bank.filter((q) => {
    const c = state.cards[q.id];
    return !c || !c.nextAt || dayDiff(d, c.nextAt) >= 0;
  }).length;
  const totalRight = cards.reduce((s, [, c]) => s + (c.right || 0), 0);
  const totalWrong = cards.reduce((s, [, c]) => s + (c.wrong || 0), 0);
  return {
    bank: bank.length, seen, due,
    right: totalRight, wrong: totalWrong,
    accuracy: totalRight + totalWrong ? Number((totalRight / (totalRight + totalWrong)).toFixed(3)) : null,
  };
}

module.exports = { getToday, answer, stats, loadBank, loadState, saveState, STATE_FILE };

// ---------------- CLI ----------------
if (require.main === module) {
  const args = process.argv.slice(2);
  const has = (f) => args.includes(f);
  const opt = (n, d) => { const i = args.indexOf(n); return i >= 0 && args[i + 1] ? args[i + 1] : d; };

  const ascii = (text) => text.replace(/[\u007f-\uffff]/g, (c) => '\\u' + c.charCodeAt(0).toString(16).padStart(4, '0'));

  if (has('--path')) { console.log(STATE_FILE); process.exit(0); }

  if (has('--reset')) {
    saveState({ version: 1, cards: {}, today: null, firstSeen: today() });
    console.log('答题记录已清空');
    process.exit(0);
  }

  if (has('--stats')) {
    const s = stats();
    if (has('--json')) {
      const o = opt('--out', null);
      const t = ascii(JSON.stringify(s, null, 2));
      if (o) fs.writeFileSync(o, t, 'utf8'); else console.log(t);
    } else {
      console.log(`题库 ${s.bank} 道，做过 ${s.seen} 道，到期 ${s.due} 道，正确率 ${s.accuracy === null ? '—' : (s.accuracy * 100).toFixed(0) + '%'}`);
    }
    process.exit(0);
  }

  if (has('--answer')) {
    const id = opt('--answer', '');
    if (!id) { console.error('用法: --answer <题号> --right|--wrong'); process.exit(2); }
    const correct = has('--right');
    if (!correct && !has('--wrong')) { console.error('要指定 --right 或 --wrong'); process.exit(2); }
    const r = answer(id, correct);
    if (has('--json')) {
      const o = opt('--out', null);
      const t = ascii(JSON.stringify(r, null, 2));
      if (o) fs.writeFileSync(o, t, 'utf8'); else console.log(t);
    } else {
      console.log(`${id} ${correct ? '记下了：会' : '记下了：不会'}，下次复习 ${r.nextAt}（${r.interval} 天后）`);
    }
    process.exit(0);
  }

  if (has('--today')) {
    const t = getToday();
    if (has('--json')) {
      const o = opt('--out', null);
      const txt = ascii(JSON.stringify(t, null, 2));
      if (o) fs.writeFileSync(o, txt, 'utf8'); else console.log(txt);
    } else {
      console.log('');
      console.log(`  今日三题  ${t.date}   已完成 ${t.done}/${t.total}`);
      console.log('');
      t.questions.forEach((q, i) => {
        if (q.type === 'code') {
          console.log(`  ${i + 1}. [编程题 · ${q.topic}] ${q.title}`);
          console.log(`     ${q.statement}`);
          console.log(`     ${q.io}`);
          console.log(`     ${q.answered ? `已作答 · ${q.answered === 'right' ? '做出来了' : '没做出'}` : '(参考答案见界面)'}`);
        } else {
          console.log(`  ${i + 1}. [${q.topic}] ${q.q}`);
          q.options.forEach((o, k) => console.log(`       ${String.fromCharCode(65 + k)}. ${o}`));
          console.log(`     (答案: ${String.fromCharCode(65 + q.answer)}) ${q.answered ? `已作答 · ${q.answered === 'right' ? '会' : '不会'}` : ''}`);
        }
        console.log('');
      });
    }
    process.exit(0);
  }

  console.error('用法: --today | --answer <id> --right|--wrong | --stats | --reset | --path');
  process.exit(2);
}
