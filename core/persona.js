/**
 * 祀 · 人格引擎（状态机 + 记忆 + 好感度）
 * ==================================================================
 * 独立模块：桌宠和状态面板都只读写同一个状态文件，互不耦合。
 *
 * 状态文件：%USERPROFILE%\.siqu\persona-state.json
 * 台词库  ：siqu\persona\persona.json
 *
 * CLI：
 *   node core/persona.js --state                       看完整状态
 *   node core/persona.js --event compile-error --repeat --json
 *   node core/persona.js --event compile-ok --json
 *   node core/persona.js --reset
 *   node core/persona.js --path
 *
 * 事件类型：
 *   compile-error  编译失败（可加 --repeat 表示同一个错又犯了）
 *   compile-ok     编译通过
 *   warning        编译通过但有警告
 *   called         源码里叫了她的名字
 *   praise         被夸（同上，但语气不同）
 *   click          用户点了她一下
 *   idle           长时间无互动
 *   night          深夜
 */
const fs = require('fs');
const os = require('os');
const path = require('path');

const HOME = process.env.SIQU_HOME || path.join(os.homedir(), '.siqu');
const STATE_FILE = path.join(HOME, 'persona-state.json');
const PERSONA_FILE = path.join(__dirname, '..', 'persona', 'persona.json');

// ---------------- 台词库 ----------------
function loadPersona() {
  const raw = fs.readFileSync(PERSONA_FILE, 'utf8').replace(/^\uFEFF/, '');
  return JSON.parse(raw);
}
const PERSONA = loadPersona();

// ---------------- 状态 ----------------
function nowISO() { return new Date().toISOString(); }

function defaultState() {
  return {
    version: 1,
    affinity: 8,              // 起始：刚认识，算不上陌生
    mood: 'idle',
    moodAt: nowISO(),
    firstSeen: nowISO(),
    lastEventAt: nowISO(),
    lastCompileAt: null,
    lastClickAt: null,       // 上次被点/被叫的时间，用来判断"冷落"
    lastJealousAt: null,     // 上次吃醋时间（冷却，避免每句都吃醋）
    counters: {
      compiles: 0, errors: 0, repeats: 0, oks: 0,
      warnings: 0, called: 0, clicks: 0, days: 1,
    },
    memory: {
      topErrors: [],          // [{short, count, lastAt}]
      recent: [],             // [{at, type, note}] 最多 30 条
      points: [],             // [{t, v}] 好感度采样，最多 300 个（画曲线用）
      daily: {},              // { 'YYYY-MM-DD': {last, min, max, n} } 保留 60 天
      facts: {},              // 自由键值，给以后扩展
    },
  };
}

function loadState() {
  try {
    const raw = fs.readFileSync(STATE_FILE, 'utf8').replace(/^\uFEFF/, '');
    const s = JSON.parse(raw);
    const d = defaultState();
    return { ...d, ...s, counters: { ...d.counters, ...(s.counters || {}) }, memory: { ...d.memory, ...(s.memory || {}) } };
  } catch (_) {
    return defaultState();
  }
}

function saveState(s) {
  try {
    fs.mkdirSync(HOME, { recursive: true });
    fs.writeFileSync(STATE_FILE, JSON.stringify(s, null, 2), 'utf8');
    return true;
  } catch (_) {
    return false;
  }
}

// ---------------- 好感度 ----------------
function levelOf(affinity) {
  const levels = PERSONA.levels || [];
  let cur = levels[0] || { min: 0, name: '陌生', visual: 'idle' };
  for (const l of levels) if (affinity >= l.min) cur = l;
  return cur;
}

function clamp(n, lo, hi) { return Math.max(lo, Math.min(hi, n)); }

// ---------------- 生日（9月15日） ----------------
function todayMD() {
  const d = new Date();
  return `${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}
function isBirthday(force) {
  if (force) return true;
  return String(PERSONA.birthday || '') === todayMD();
}

// ---------------- 台词 ----------------
function pick(arr) {
  if (!arr || !arr.length) return '';
  return arr[Math.floor(Math.random() * arr.length)];
}

function say(pool, vars) {
  let line = pick(pool);
  for (const [k, v] of Object.entries(vars || {})) {
    line = line.split(`{${k}}`).join(String(v));
  }
  return line;
}

// ---------------- 事件处理 ----------------
/**
 * 处理一个事件，返回：
 *   { mood, visual, line, detail, affinity, level, moodChanged }
 */
function applyEvent(event, opts = {}) {
  const s = loadState();
  const prevMood = s.mood;
  const c = s.counters;
  const lines = PERSONA.lines || {};
  // 测试用：SIQU_FAKE_HOUR=2 可以假装现在是凌晨 2 点（预览"犯困"等时间相关行为）
  const hour = process.env.SIQU_FAKE_HOUR ? Number(process.env.SIQU_FAKE_HOUR) : new Date().getHours();

  let line = '';
  let detail = '';
  let mood = s.mood;
  let delta = 0;

  switch (event) {
    case 'compile-error': {
      c.errors++;
      s.lastCompileAt = nowISO();
      if (opts.repeat) {
        c.repeats++;
        delta = -1;
        mood = 'taunt';
        line = say(lines.compileErrorRepeat, { count: opts.count || 2 });
        detail = opts.short || '';
      } else if (opts.known) {
        // 规则库已经认识的错：语气是嫌弃，但台词交给规则库自己说
        delta = 0.3;
        mood = 'taunt';
        line = '';
        detail = opts.short || '';
      } else {
        delta = 0.5;
        mood = 'confused';
        line = say(lines.compileErrorFirst, {});
        detail = opts.short || '';
      }
      // 连续犯错会积累不满
      if (c.errors - c.oks >= 3) mood = 'taunt';
      break;
    }

    case 'compile-ok': {
      c.compiles++;
      c.oks++;
      s.lastCompileAt = nowISO();
      delta = 1;

      // 吃了很多错误之后终于过了 → 高兴；一向很顺 → 太平淡
      if (c.errors >= 2 && opts.afterError) {
        mood = 'happy';
        line = say(lines.compileOkAfterStruggle, {});
      } else {
        mood = 'idle';
        line = say(lines.compileOk, {});
      }

      // 长时间只写代码不理她 → 吃醋（带 15 分钟冷却，不然每句都在吃醋）
      const lastClickMs = s.lastClickAt ? Date.parse(s.lastClickAt) : 0;
      const sinceClickMin = lastClickMs ? (Date.now() - lastClickMs) / 60000 : 999;
      const lastJelMs = s.lastJealousAt ? Date.parse(s.lastJealousAt) : 0;
      const sinceJelMin = lastJelMs ? (Date.now() - lastJelMs) / 60000 : 999;
      if (sinceClickMin > 20 && c.compiles >= 2 && s.affinity >= 10 && sinceJelMin > 15) {
        mood = 'jealous';
        line = say(lines.jealous, { minutes: Math.round(sinceClickMin) });
        delta = -0.5;
        s.lastJealousAt = nowISO();
      }
      break;
    }

    case 'warning': {
      c.warnings++;
      delta = 0.2;
      mood = 'confused';
      line = say(lines.warning, {});
      detail = opts.short || '';
      break;
    }

    case 'called':
    case 'praise': {
      c.called++;
      s.lastClickAt = nowISO();
      delta = event === 'called' ? 3 : 2.5;
      mood = 'embarrassed';
      line = say(event === 'called' ? lines.called : lines.praise, {});
      break;
    }

    case 'click': {
      c.clicks++;
      s.lastClickAt = nowISO();
      // 连续点她：第 5、10、15… 次会进入「赌气」
      if (c.clicks % 5 === 0) {
        delta = -0.5;
        mood = 'pout';
        line = say(lines.pout, {});
      } else if (lines.clickTaunt && lines.clickTaunt.length) {
        // 点击专用台词（含"呆货"）—— 桌宠会据此播放语音
        delta = 0.2;
        mood = 'taunt';
        line = say(lines.clickTaunt, {});
      } else {
        delta = 0.2;
        mood = s.mood === 'idle' ? 'idle' : s.mood;
        line = say(lines.idleClick, {});
      }
      break;
    }

    case 'quiz-right': {
      // 每日三题答对
      delta = 1.5;
      mood = 'happy';
      line = say(lines.quizRight, {});
      break;
    }

    case 'quiz-wrong': {
      // 每日三题答错
      delta = -0.5;
      mood = 'confused';
      line = say(lines.quizWrong, {});
      break;
    }

    case 'idle': {
      // 深夜（23:00–07:00）她会犯困
      if (hour >= 23 || hour < 7) {
        mood = 'sleep';
        line = say(lines.sleep, {});
      } else {
        mood = s.affinity > 55 ? 'confused' : 'idle';
        line = say(lines.idle, {});
      }
      break;
    }

    case 'night': {
      if (hour >= 23 || hour < 5) {
        mood = 'confused';
        delta = 0.5;
        line = say(lines.night, {});
      } else {
        line = '';
      }
      break;
    }

    case 'longAbsence': {
      delta = -1;
      mood = 'taunt';
      line = say(lines.longAbsence, {});
      break;
    }

    case 'crash': {
      // 程序运行时崩溃（段错误、除零…）
      delta = -0.5;
      mood = 'taunt';
      line = say(lines.crash, {});
      detail = opts.short || '';
      break;
    }

    case 'birthday': {
      // 只有她生日当天才有台词（测试时用 --force-birthday）
      if (isBirthday(opts.forceBirthday)) {
        mood = 'embarrassed';
        delta = 2;
        line = say(lines.birthday, {});
        detail = '九月十五';
      } else {
        line = '';
      }
      break;
    }

    default:
      line = '';
  }

  // 好感度结算（上限 100，下限 0）
  s.affinity = clamp(s.affinity + delta, 0, 100);
  const lv = levelOf(s.affinity);

  if (mood !== prevMood) s.moodAt = nowISO();
  s.mood = mood;
  s.lastEventAt = nowISO();

  // 记忆：最近事件（最多 30 条）
  // note 优先存"她实际说的那句话"——面板里看起来才有意思
  if (event !== 'idle') {
    const note = (opts.said || line || detail || '').slice(0, 160);
    s.memory.recent.unshift({ at: nowISO(), type: event, note: note });
    s.memory.recent = s.memory.recent.slice(0, 30);
  }

  // 记忆：常犯的错（最多 20 条）
  if (event === 'compile-error' && detail) {
    const hit = s.memory.topErrors.find((e) => e.short === detail);
    if (hit) { hit.count++; hit.lastAt = nowISO(); }
    else s.memory.topErrors.unshift({ short: detail, count: 1, lastAt: nowISO() });
    s.memory.topErrors.sort((a, b) => b.count - a.count);
    s.memory.topErrors = s.memory.topErrors.slice(0, 20);
  }

  const saved = saveState(s);

  // 好感度历史（画曲线用）
  // points：细粒度采样（当天能看出波动）；daily：跨天汇总（看长期趋势）
  if (delta !== 0) {
    s.memory.points.push({ t: nowISO(), v: Number(s.affinity.toFixed(1)) });
    if (s.memory.points.length > 300) s.memory.points = s.memory.points.slice(-300);

    const day = nowISO().slice(0, 10);
    const d = s.memory.daily[day] || { last: s.affinity, min: s.affinity, max: s.affinity, n: 0 };
    d.last = Number(s.affinity.toFixed(1));
    d.min = Math.min(d.min, d.last);
    d.max = Math.max(d.max, d.last);
    d.n = (d.n || 0) + 1;
    s.memory.daily[day] = d;

    const days = Object.keys(s.memory.daily).sort();
    if (days.length > 60) {
      for (const k of days.slice(0, days.length - 60)) delete s.memory.daily[k];
    }
    saveState(s);
  }

  // 撤回机制：说漏嘴之后有一定概率补一句"撤回"
  // （原作里她就是这样——说完立刻否认，再假装什么都没发生）
  let followUp = '';
  if (mood === 'embarrassed' && Math.random() < 0.65) {
    followUp = say(lines.retract, {});
  } else if (mood === 'pout' && Math.random() < 0.4) {
    followUp = say(lines.retract, {});
  }

  return {
    mood,
    visual: (PERSONA.moods[mood] || {}).visual || 'idle',
    label: (PERSONA.moods[mood] || {}).label || mood,
    line,
    followUp,
    detail,
    affinity: Number(s.affinity.toFixed(1)),
    level: lv.name,
    levelNote: lv.note || '',
    moodChanged: mood !== prevMood,
    delta: Number(delta.toFixed(1)),
    saved,
  };
}

module.exports = { applyEvent, loadState, saveState, defaultState, levelOf, STATE_FILE, PERSONA_FILE };

// ---------------- CLI ----------------
if (require.main === module) {
  const args = process.argv.slice(2);
  const has = (f) => args.includes(f);
  const opt = (n, d) => { const i = args.indexOf(n); return i >= 0 && args[i + 1] ? args[i + 1] : d; };

  if (has('--path')) { console.log(STATE_FILE); process.exit(0); }

  if (has('--reset')) {
    saveState(defaultState());
    console.log('人格状态已重置');
    process.exit(0);
  }

  if (has('--state')) {
    const s = loadState();
    const lv = levelOf(s.affinity);
    if (has('--json')) {
      const text = JSON.stringify({ ...s, level: lv.name }, null, 2);
      const ascii = text.replace(/[\u007f-\uffff]/g, (ch) => '\\u' + ch.charCodeAt(0).toString(16).padStart(4, '0'));
      const outF = opt('--out', null);
      if (outF) fs.writeFileSync(outF, ascii, 'utf8'); else console.log(ascii);
    } else {
      console.log('');
      console.log(`  好感度 ${s.affinity.toFixed(1)} / 100   ${lv.name}`);
      console.log(`  心情   ${(PERSONA.moods[s.mood] || {}).label || s.mood}`);
      console.log(`  统计   编译 ${s.counters.compiles} 次 / 错误 ${s.counters.errors} 次 / 重复错误 ${s.counters.repeats} 次 / 被叫 ${s.counters.called} 次`);
      console.log('');
      if (s.memory.topErrors.length) {
        console.log('  常犯的错：');
        s.memory.topErrors.slice(0, 5).forEach((e, i) => console.log(`    ${i + 1}. [${e.count} 次] ${e.short}`));
      }
      console.log('');
    }
    process.exit(0);
  }

  const event = opt('--event', null);
  if (!event) {
    console.error('用法: node persona.js --event <类型> [--repeat] [--short 说明] [--json] [--out 文件]');
    console.error('       node persona.js --state | --reset | --path');
    process.exit(2);
  }

  const res = applyEvent(event, {
    repeat: has('--repeat'),
    known: has('--known'),
    forceBirthday: has('--force-birthday'),
    count: Number(opt('--count', 2)),
    short: opt('--short', ''),
    said: opt('--said', ''),
    afterError: has('--after-error'),
  });

  if (has('--json')) {
    const text = JSON.stringify(res, null, 2);
    const ascii = text.replace(/[\u007f-\uffff]/g, (ch) => '\\u' + ch.charCodeAt(0).toString(16).padStart(4, '0'));
    const outF = opt('--out', null);
    if (outF) fs.writeFileSync(outF, ascii, 'utf8'); else console.log(ascii);
  } else {
    console.log(`心情: ${res.label}  好感度: ${res.affinity} (${res.delta >= 0 ? '+' : ''}${res.delta})  ${res.level}`);
    if (res.line) console.log(`祀：「${res.line}」`);
    if (res.detail) console.log(`附注: ${res.detail}`);
  }
}
