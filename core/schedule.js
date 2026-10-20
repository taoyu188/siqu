/**
 * 终末地日程引擎
 * ------------------------------------------------------------------
 * 只做本地计算，不联网、不需要账号：
 *   1. 每日 / 每周重置倒计时（服务器 04:00）
 *   2. 理智推算（给一次快照，按恢复速度往后算，封顶）
 *   3. 每日/每周任务清单的勾选状态（按游戏日/游戏周自动重置）
 *
 * 用法：
 *   node core/schedule.js --now                人读的日程摘要
 *   node core/schedule.js --json --out x.json  给界面用的结构化数据
 *   node core/schedule.js --done d2            勾上一条
 *   node core/schedule.js --undo d2            取消勾选
 *   node core/schedule.js --check-all daily    一键全勾
 *   node core/schedule.js --snapshot 180       记录一次理智快照
 *   node core/schedule.js --reset              清空状态
 *
 * 状态文件：%SIQU_HOME%|%USERPROFILE%\.siqu\schedule-state.json
 */
const fs = require('fs');
const os = require('os');
const path = require('path');

const appRoot = path.dirname(__dirname);
const cfgPath = path.join(appRoot, 'game', 'schedule.json');

function homeDir() {
  if (process.env.SIQU_HOME) return process.env.SIQU_HOME;
  return path.join(os.homedir(), '.siqu');
}
const statePath = path.join(homeDir(), 'schedule-state.json');

function loadCfg() {
  return JSON.parse(fs.readFileSync(cfgPath, 'utf8').replace(/^\uFEFF/, ''));
}

function loadState() {
  try {
    return JSON.parse(fs.readFileSync(statePath, 'utf8').replace(/^\uFEFF/, ''));
  } catch {
    return { daily: {}, weekly: {}, stamina: null };
  }
}

function saveState(s) {
  fs.mkdirSync(homeDir(), { recursive: true });
  fs.writeFileSync(statePath, JSON.stringify(s, null, 2), 'utf8');
}

// ---------------- 时间计算 ----------------
function pad(n) { return String(n).padStart(2, '0'); }
function dateKey(d) { return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`; }

/** 当前游戏日（04:00 之前算前一天） */
function gameDay(now, resetHour) {
  const d = new Date(now);
  if (d.getHours() < resetHour) d.setDate(d.getDate() - 1);
  return dateKey(d);
}

/** 下一个每日重置时刻 */
function nextDailyReset(now, resetHour) {
  const d = new Date(now);
  d.setHours(resetHour, 0, 0, 0);
  if (d <= now) d.setDate(d.getDate() + 1);
  return d;
}

/** 下一个每周重置时刻（resetWeekday: 1=周一） */
function nextWeeklyReset(now, resetHour, resetWeekday) {
  const d = new Date(now);
  d.setHours(resetHour, 0, 0, 0);
  const diff = (resetWeekday - d.getDay() + 7) % 7;
  d.setDate(d.getDate() + diff);
  if (d <= now) d.setDate(d.getDate() + 7);
  return d;
}

/** 当前游戏周（以每周重置日为准） */
function gameWeek(now, resetHour, resetWeekday) {
  const d = new Date(now);
  if (d.getHours() < resetHour) d.setDate(d.getDate() - 1);
  const diff = (d.getDay() - resetWeekday + 7) % 7;
  d.setDate(d.getDate() - diff);
  return dateKey(d);
}

function minutesBetween(a, b) { return Math.floor((b - a) / 60000); }

function humanLeft(ms) {
  const m = Math.floor(ms / 60000);
  const d = Math.floor(m / 1440);
  const h = Math.floor((m % 1440) / 60);
  const mm = m % 60;
  if (d > 0) return `${d}天${h}小时`;
  if (h > 0) return `${h}小时${mm}分`;
  return `${mm}分钟`;
}

// ---------------- 理智推算 ----------------
function staminaNow(cfg, state, now) {
  const s = cfg.stamina;
  const snap = state.stamina;
  if (!snap || typeof snap.value !== 'number') return null;
  const elapsed = Math.max(0, minutesBetween(new Date(snap.at), now));
  const gain = Math.floor(elapsed / Math.max(1, s.recoverMinutes));
  const value = Math.min(s.max, snap.value + gain);
  return {
    value,
    max: s.max,
    at: snap.at,
    full: value >= s.max,
    percent: Math.round((value / s.max) * 100),
    fillMinutes: value >= s.max ? 0 : (s.max - value) * s.recoverMinutes,
  };
}

// ---------------- 任务状态 ----------------
function taskStatus(cfg, state, now) {
  const rh = cfg.server.resetHour;
  const wrh = cfg.weekly.resetHour;
  const wd = cfg.weekly.resetWeekday;
  const day = gameDay(now, rh);
  const week = gameWeek(now, rh, wd);

  const dailyDone = state.daily && state.daily.day === day ? state.daily.done || [] : [];
  const weeklyDone = state.weekly && state.weekly.week === week ? state.weekly.done || [] : [];

  const build = (list, done) => list.map((t) => ({ ...t, done: done.includes(t.id) }));

  const daily = build(cfg.tasks.daily || [], dailyDone);
  const weekly = build(cfg.tasks.weekly || [], weeklyDone);

  return {
    day,
    week,
    daily,
    weekly,
    dailyPending: daily.filter((t) => !t.done).length,
    weeklyPending: weekly.filter((t) => !t.done).length,
  };
}

// ---------------- 森空岛实时数据（可选） ----------------
const remoteCachePath = () => path.join(homeDir(), 'endfield-cache.json');
const REMOTE_TTL_MS = 120000;

function readRemoteCache() {
  try {
    const c = JSON.parse(fs.readFileSync(remoteCachePath(), 'utf8').replace(/^\uFEFF/, ''));
    if (c && c.at && Date.now() - c.at < REMOTE_TTL_MS) return c.payload;
  } catch (e) { /* ignore */ }
  return null;
}
function writeRemoteCache(payload) {
  try {
    fs.mkdirSync(homeDir(), { recursive: true });
    fs.writeFileSync(remoteCachePath(), JSON.stringify({ at: Date.now(), payload }, null, 2), 'utf8');
  } catch (e) { /* ignore */ }
}

async function getRemote() {
  const cached = readRemoteCache();
  if (cached) return cached;
  try {
    const sk = require(path.join(__dirname, 'skland.js'));
    const cred = sk.loadCred();
    if (!cred) return null;
    const bindings = await sk.getBindings(cred);
    const all = sk.allEndfields(bindings).filter((e) => !e.noRole);
    if (!all.length) return null;
    const pick = cred.endfieldRoleId
      ? all.find((e) => e.roleId === String(cred.endfieldRoleId))
      : (all.find((e) => e.isDefault) || all[0]);
    if (!pick) return null;
    const res = await sk.getEndfieldCard(cred, pick);
    const payload = { account: pick, summary: res.summary };
    writeRemoteCache(payload);
    return payload;
  } catch (e) {
    return { error: e.message };
  }
}

// ---------------- 汇总 ----------------
function buildStatus(now, remote) {
  const cfg = loadCfg();
  const state = loadState();

  const dReset = nextDailyReset(now, cfg.server.resetHour);
  const wReset = nextWeeklyReset(now, cfg.weekly.resetHour, cfg.weekly.resetWeekday);
  const st = taskStatus(cfg, state, now);

  // 理智：优先用森空岛实时值，其次本地快照推算
  let stam = null;
  let stamSource = 'none';
  if (remote && remote.summary && remote.summary.stamina) {
    const rs = remote.summary.stamina;
    stam = {
      value: rs.current,
      max: rs.max,
      full: rs.current >= rs.max,
      percent: Math.round((rs.current / rs.max) * 100),
      fillMinutes: rs.fullInSeconds === null ? 0 : Math.round(rs.fullInSeconds / 60),
      minutesPerPoint: rs.minutesPerPoint,
    };
    stamSource = 'remote';
  } else {
    stam = staminaNow(cfg, state, now);
    if (stam) stamSource = 'local';
  }

  const out = {
    now: now.toISOString(),
    game: cfg.game,
    daily: {
      resetAt: dReset.toISOString(),
      resetInMinutes: minutesBetween(now, dReset),
      resetInText: humanLeft(dReset - now),
      gameDay: st.day,
      pending: st.dailyPending,
      tasks: st.daily,
    },
    weekly: {
      resetAt: wReset.toISOString(),
      resetInText: humanLeft(wReset - now),
      gameWeek: st.week,
      pending: st.weeklyPending,
      tasks: st.weekly,
    },
    stamina: stam,
    staminaSource: stamSource,
    staminaCfg: {
      max: cfg.stamina.max,
      recoverMinutes: cfg.stamina.recoverMinutes,
      unit: cfg.stamina.unit,
      verify: !!cfg.stamina._verify,
    },
    reminders: cfg.reminders,
  };

  // 森空岛给的真实任务进度
  if (remote && remote.summary) {
    const s = remote.summary;
    out.remote = {
      ok: true,
      account: remote.account ? {
        nickName: remote.account.nickName, level: remote.account.level,
        serverName: remote.account.serverName, roleId: remote.account.roleId,
      } : null,
      fetchedAt: new Date().toISOString(),
      dailyActivation: s.daily ? { value: s.daily.dailyActivation, max: s.daily.maxDailyActivation } : null,
      weeklyScore: s.weekly ? { value: s.weekly.score, total: s.weekly.total } : null,
    };
  } else if (remote && remote.error) {
    out.remote = { ok: false, error: remote.error };
  }

  return out;
}

// ---------------- 输出 ----------------
function printHuman(status) {
  console.log('');
  console.log(`  ${status.game}   今日：${status.daily.gameDay}`);
  if (status.remote && status.remote.ok && status.remote.account) {
    const a = status.remote.account;
    console.log(`  账号：${a.nickName}  Lv.${a.level}  ${a.serverName}`);
  }
  console.log('');
  console.log(`  距每日重置  ${status.daily.resetInText}（${new Date(status.daily.resetAt).toTimeString().slice(0, 5)}）`);
  console.log(`  距每周重置  ${status.weekly.resetInText}`);
  console.log('');

  if (status.remote && status.remote.ok) {
    if (status.remote.dailyActivation) {
      const d = status.remote.dailyActivation;
      console.log(`  每日活跃    ${d.value} / ${d.max}${d.value >= d.max ? '  已完成' : ''}`);
    }
    if (status.remote.weeklyScore) {
      const w = status.remote.weeklyScore;
      console.log(`  每周进度    ${w.value} / ${w.total}`);
    }
    console.log('  （以上来自森空岛实时数据）');
    console.log('');
    console.log(`  手动清单  待办 ${status.daily.pending}/${status.daily.tasks.length}`);
    for (const t of status.daily.tasks) {
      console.log(`    ${t.done ? '[x]' : '[ ]'} ${t.name}${t.done ? '' : '   — ' + t.hint}`);
    }
    if (status.weekly.tasks.length) {
      console.log('');
      console.log(`  每周清单  待办 ${status.weekly.pending}/${status.weekly.tasks.length}`);
      for (const t of status.weekly.tasks) {
        console.log(`    ${t.done ? '[x]' : '[ ]'} ${t.name}${t.done ? '' : '   — ' + t.hint}`);
      }
    }
  } else {
    if (status.remote && status.remote.error) {
      console.log(`  ⚠ 森空岛读取失败：${status.remote.error}`);
    }
    console.log(`  每日任务  待办 ${status.daily.pending}/${status.daily.tasks.length}`);
    for (const t of status.daily.tasks) {
      console.log(`    ${t.done ? '[x]' : '[ ]'} ${t.name}${t.done ? '' : '   — ' + t.hint}`);
    }
    if (status.weekly.tasks.length) {
      console.log('');
      console.log(`  每周任务  待办 ${status.weekly.pending}/${status.weekly.tasks.length}`);
      for (const t of status.weekly.tasks) {
        console.log(`    ${t.done ? '[x]' : '[ ]'} ${t.name}${t.done ? '' : '   — ' + t.hint}`);
      }
    }
  }

  console.log('');
  if (status.stamina) {
    const st = status.stamina;
    const src = status.staminaSource === 'remote' ? '森空岛实时' : '本地推算';
    console.log(`  ${status.staminaCfg.unit}  ${st.value}/${st.max}（${st.percent}%）  [${src}]`);
    if (!st.full) console.log(`        回满还需 ${humanLeft(st.fillMinutes * 60000)}`);
    else console.log('        已满，会溢出');
  } else {
    console.log(`  ${status.staminaCfg.unit}  无数据：登录森空岛（node core/skland.js --qr）或记录快照`);
  }
  if (status.staminaCfg.verify) {
    console.log(`  ⚠ 理智上限/恢复速度未确认（game/schedule.json）`);
  }
  console.log('');
}

// ---------------- 命令行 ----------------
const args = process.argv.slice(2);
const has = (f) => args.includes(f);
const opt = (n, d) => { const i = args.indexOf(n); return i >= 0 && args[i + 1] ? args[i + 1] : d; };

// SIQU_FAKE_NOW 仅用于测试提醒逻辑（形如 "2026-10-21T03:35:00"）
const now = process.env.SIQU_FAKE_NOW ? new Date(process.env.SIQU_FAKE_NOW) : new Date();

if (has('--reset')) {
  if (fs.existsSync(statePath)) fs.unlinkSync(statePath);
  console.log('日程状态已清空');
  process.exit(0);
}

if (has('--done') || has('--undo') || has('--check-all')) {
  const cfg = loadCfg();
  const state = loadState();
  const rh = cfg.server.resetHour;
  const day = gameDay(now, rh);
  const week = gameWeek(now, rh, cfg.weekly.resetHour, cfg.weekly.resetWeekday);

  if (!state.daily || state.daily.day !== day) state.daily = { day, done: [] };
  if (!state.weekly || state.weekly.week !== week) state.weekly = { week, done: [] };

  const allDaily = (cfg.tasks.daily || []).map((t) => t.id);
  const allWeekly = (cfg.tasks.weekly || []).map((t) => t.id);

  if (has('--check-all')) {
    const group = opt('--check-all', 'daily');
    if (group === 'daily') state.daily.done = allDaily.slice();
    else state.weekly.done = allWeekly.slice();
    saveState(state);
    console.log(`已勾选全部 ${group}`);
    process.exit(0);
  }

  const id = has('--done') ? opt('--done', '') : opt('--undo', '');
  const isDaily = allDaily.includes(id);
  const isWeekly = allWeekly.includes(id);
  if (!isDaily && !isWeekly) {
    console.error(`未知任务 id：${id}`);
    console.error(`每日：${allDaily.join(', ')}`);
    console.error(`每周：${allWeekly.join(', ')}`);
    process.exit(2);
  }
  const bucket = isDaily ? state.daily : state.weekly;
  if (has('--done')) { if (!bucket.done.includes(id)) bucket.done.push(id); }
  else bucket.done = bucket.done.filter((x) => x !== id);
  saveState(state);
  console.log(`${has('--done') ? '已勾选' : '已取消'} ${id}`);
  process.exit(0);
}

if (has('--snapshot')) {
  const cfg = loadCfg();
  const state = loadState();
  const v = Number(opt('--snapshot', ''));
  if (Number.isNaN(v)) { console.error('用法：--snapshot <当前理智数>'); process.exit(2); }
  state.stamina = { value: Math.max(0, Math.min(cfg.stamina.max, v)), at: now.toISOString() };
  saveState(state);
  console.log(`已记录理智快照：${state.stamina.value}/${cfg.stamina.max}`);
  process.exit(0);
}
(async () => {
  const status = buildStatus(now, has('--no-remote') ? null : await getRemote());
  if (has('--json')) {
    const outPath = opt('--out', '');
    const s = JSON.stringify(status, null, 2);
    if (outPath) { fs.writeFileSync(outPath, s, 'utf8'); console.log('已写入 ' + outPath); }
    else console.log(s);
    return;
  }
  printHuman(status);
})();