/**
 * 角色包管理（换立绘 / 换语音）
 * ------------------------------------------------------------------
 * 一个「角色包」= 8 张表情图 + 可选点击语音 + 台词库。
 * 放在 characters/<id>/ 下，用 roles/roles.json 注册。
 *
 * 用法：
 *   node tools/character.js --list                看有哪些角色、缺什么
 *   node tools/character.js --use <id>            切换当前角色
 *   node tools/character.js --new <id> [--name X] 新建一个角色包（用占位图打底）
 *   node tools/character.js --import <目录> --id <id> [--name X] [--audio <文件>]
 *                                                 从目录导入图片（按 idle.png 等命名）
 *   node tools/character.js --set-audio <id> --file <文件> [--trigger 词] [--volume 0.8]
 *   node tools/character.js --clear-audio <id>
 *   node tools/character.js --check [--id <id>]   校验图片/音频
 *   node tools/character.js --remove <id>         从列表移除（不删文件）
 */
const fs = require('fs');
const path = require('path');

const appRoot = path.dirname(__dirname);
const rolesPath = path.join(appRoot, 'roles', 'roles.json');
const activePath = path.join(appRoot, 'roles', 'active.txt');
const charRoot = path.join(appRoot, 'characters');

const STATES = ['idle', 'happy', 'taunt', 'confused', 'embarrassed', 'jealous', 'pout', 'sleep'];
const IMG_EXT = ['.png', '.jpg', '.jpeg', '.webp'];
const AUDIO_EXT = ['.wav', '.mp3', '.m4a', '.ogg', '.flac'];

const args = process.argv.slice(2);
const has = (f) => args.includes(f);
const opt = (n, d) => { const i = args.indexOf(n); return i >= 0 && args[i + 1] ? args[i + 1] : d; };

function load() {
  const raw = fs.readFileSync(rolesPath, 'utf8').replace(/^\uFEFF/, '');
  return JSON.parse(raw);
}
function save(db) {
  let s = JSON.stringify(db, null, 2);
  s = s.replace(/\\u([0-9a-fA-F]{4})/g, (m, h) => String.fromCharCode(parseInt(h, 16)));
  fs.writeFileSync(rolesPath, s, 'utf8');
}

function abs(p) { return path.isAbsolute(p) ? p : path.join(appRoot, p); }

/** 当前生效的角色 id：roles/active.txt 优先于 roles.json 的 defaultRole */
function currentId(db) {
  try {
    const t = fs.readFileSync(activePath, 'utf8').trim();
    if (t && db.roles.some((r) => r.id === t)) return t;
  } catch (e) { /* 没有就用默认 */ }
  return db.defaultRole;
}

function checkImage(file) {
  const problems = [];
  try {
    const st = fs.statSync(file);
    if (!st.size) problems.push('文件是空的');
    const head = Buffer.alloc(12);
    const fd = fs.openSync(file, 'r');
    fs.readSync(fd, head, 0, 12, 0);
    fs.closeSync(fd);
    const isPng = head.slice(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]));
    const isJpg = head[0] === 0xff && head[1] === 0xd8;
    if (!isPng && !isJpg) problems.push('不是 PNG/JPG（WebP 可能显示不出来）');
    return { ok: problems.length === 0, problems, size: st.size };
  } catch (e) {
    return { ok: false, problems: ['读不到文件：' + e.message] };
  }
}

function roleReport(role) {
  const issues = [];
  const rows = [];
  for (const s of STATES) {
    const rel = role.images ? role.images[s] : null;
    if (!rel) { issues.push(`缺少 ${s}`); rows.push([s, '—', '未配置']); continue; }
    const full = abs(rel);
    if (!fs.existsSync(full)) { issues.push(`缺少 ${s}（${rel}）`); rows.push([s, rel, '文件不存在']); continue; }
    const r = checkImage(full);
    if (!r.ok) issues.push(`${s}: ${r.problems.join('；')}`);
    rows.push([s, rel, r.ok ? `${(r.size / 1024).toFixed(0)} KB` : r.problems.join('；')]);
  }
  // 多余的表情图（不影响运行，只提示）
  const dir = role.images && role.images.idle ? path.dirname(abs(role.images.idle)) : null;
  // 只有独立角色包目录（characters/<id>/images）才检查多余文件
  const isPackDir = dir && dir.replace(/\\/g, '/').includes('/characters/');
  if (isPackDir && fs.existsSync(dir)) {
    const extra = fs.readdirSync(dir).filter((f) => IMG_EXT.includes(path.extname(f).toLowerCase()))
      .map((f) => path.basename(f, path.extname(f)))
      .filter((n) => !STATES.includes(n));
    if (extra.length) issues.push(`目录里有未使用的图：${extra.join(', ')}`);
  }
  // 音频
  let audioInfo = '无';
  if (role.audio && role.audio.click && role.audio.click.file) {
    const af = abs(role.audio.click.file);
    if (!fs.existsSync(af)) issues.push(`语音文件不存在（${role.audio.click.file}）`);
    else if (!AUDIO_EXT.includes(path.extname(af).toLowerCase())) issues.push(`语音格式可能不支持：${path.extname(af)}`);
    else audioInfo = role.audio.click.file + (role.audio.click.triggerText ? `（只在台词含「${role.audio.click.triggerText}」时播）` : '');
  } else if (role.audio && role.audio.click === null) {
    audioInfo = '该角色声明无语音';
  }
  // 台词库
  let personaInfo = '默认';
  if (role.persona) {
    const pp = abs(role.persona);
    if (!fs.existsSync(pp)) issues.push(`台词库不存在（${role.persona}）`);
    else personaInfo = role.persona;
  }
  return { issues, rows, audioInfo, personaInfo };
}

// ---------------- 命令 ----------------
if (has('--list') || args.length === 0) {
  const db = load();
  console.log('');
  console.log(`  角色包（current = ${currentId(db)}）`);
  console.log('');
  for (const role of db.roles) {
    const rep = roleReport(role);
    const mark = role.id === currentId(db) ? ' ← 当前' : '';
    const status = rep.issues.length ? `⚠ ${rep.issues.length} 个问题` : '✓ 完整';
    console.log(`  [${role.id}]  ${role.name}${mark}   ${status}`);
    console.log(`      语音：${rep.audioInfo}`);
    console.log(`      台词：${rep.personaInfo}`);
    if (rep.issues.length) rep.issues.forEach((i) => console.log(`      · ${i}`));
    console.log('');
  }
  console.log('  切换：node tools/character.js --use <id>');
  console.log('  新建：node tools/character.js --new mychar --name 我的角色');
  console.log('');
  process.exit(0);
}

if (has('--use')) {
  const id = opt('--use', '');
  const db = load();
  const role = db.roles.find((r) => r.id === id);
  if (!role) { console.error(`没有角色 ${id}，已有：${db.roles.map((r) => r.id).join(', ')}`); process.exit(2); }
  fs.writeFileSync(activePath, id + '\r\n', 'utf8');
  console.log(`  已切换到「${role.name}」(${id})。重启桌宠生效。`);
  console.log(`  （写在 roles/active.txt，这个文件不进 git，换电脑记得重设）`);
  process.exit(0);
}

if (has('--new')) {
  const id = opt('--new', '');
  const name = opt('--name', id);
  if (!id) { console.error('--new 需要角色 id'); process.exit(2); }
  const db = load();
  if (db.roles.some((r) => r.id === id)) { console.error(`角色 ${id} 已存在`); process.exit(2); }

  const dir = path.join(charRoot, id, 'images');
  fs.mkdirSync(dir, { recursive: true });
  // 用占位图打底，保证开箱能跑
  const phDir = path.join(charRoot, 'placeholder', 'images');
  let copied = 0;
  for (const s of STATES) {
    const src = path.join(phDir, `${s}.png`);
    if (fs.existsSync(src)) { fs.copyFileSync(src, path.join(dir, `${s}.png`)); copied++; }
  }
  fs.writeFileSync(path.join(charRoot, id, 'README.txt'),
    [
      `角色包：${name} (${id})`,
      '',
      '把 8 张表情图放进 images/ 目录，文件名必须是：',
      ...STATES.map((s) => `  ${s}.png`),
      '',
      '要求：',
      '  · PNG 透明背景，正方形，建议 512x512 或更大',
      '  · 头顶留一点空白（桌宠按底部对齐）',
      '  · 缺哪张会自动回退到 idle.png',
      '',
      '换语音：node tools/character.js --set-audio ' + id + ' --file 你的音频.m4a',
      '校验：  node tools/character.js --check --id ' + id,
      '',
    ].join('\r\n'), 'utf8');

  const images = {};
  for (const s of STATES) images[s] = `characters/${id}/images/${s}.png`;
  db.roles.push({ id, name, scale: 1.0, images, audio: { click: null }, persona: 'persona/persona.json' });
  save(db);
  console.log('');
  console.log(`  已创建角色包「${name}」(id=${id})`);
  console.log(`    目录：characters\\${id}\\images\\  （已放好 ${copied} 张占位图）`);
  console.log(`    下一步：把它们换成你的图，然后 node tools/character.js --use ${id}`);
  console.log('');
  process.exit(0);
}

if (has('--import')) {
  const src = opt('--import', '');
  const id = opt('--id', path.basename(src || 'mychar'));
  const name = opt('--name', id);
  const audio = opt('--audio', '');
  if (!src || !fs.existsSync(src)) { console.error('目录不存在：' + src); process.exit(2); }

  const db = load();
  if (db.roles.some((r) => r.id === id)) { console.error(`角色 ${id} 已存在，换个 id 或先 --remove`); process.exit(2); }

  const dir = path.join(charRoot, id, 'images');
  fs.mkdirSync(dir, { recursive: true });

  // 收集源目录里的图：按 idle.png/idle.jpg 或 idle 匹配
  const files = fs.readdirSync(src, { withFileTypes: true }).filter((e) => e.isFile());
  const found = {};
  for (const f of files) {
    const ext = path.extname(f.name).toLowerCase();
    if (!IMG_EXT.includes(ext)) continue;
    const base = path.basename(f.name, path.extname(f.name)).toLowerCase().trim();
    if (STATES.includes(base) && !found[base]) found[base] = f.name;
  }
  const missing = STATES.filter((s) => !found[s]);
  if (!Object.keys(found).length) {
    console.error('源目录里没有找到任何按 idle.png / happy.png 命名的图片。');
    console.error('需要的文件名：' + STATES.join(', '));
    process.exit(2);
  }

  for (const s of Object.keys(found)) {
    const ext = path.extname(found[s]);
    fs.copyFileSync(path.join(src, found[s]), path.join(dir, `${s}${ext}`));
  }
  // 缺失的用占位图补齐，保证能跑
  const phDir = path.join(charRoot, 'placeholder', 'images');
  for (const s of missing) {
    const p = path.join(phDir, `${s}.png`);
    if (fs.existsSync(p)) fs.copyFileSync(p, path.join(dir, `${s}.png`));
  }

  const images = {};
  for (const s of STATES) {
    const ext = found[s] ? path.extname(found[s]) : '.png';
    images[s] = `characters/${id}/images/${s}${ext}`;
  }
  let audioCfg = null;
  if (audio && fs.existsSync(audio)) {
    fs.mkdirSync(path.join(charRoot, id, 'audio'), { recursive: true });
    const dest = path.join(charRoot, id, 'audio', path.basename(audio));
    fs.copyFileSync(audio, dest);
    audioCfg = { file: `characters/${id}/audio/${path.basename(audio)}`, volume: 0.85, triggerText: '' };
  }
  db.roles.push({ id, name, scale: 1.0, images, audio: { click: audioCfg }, persona: 'persona/persona.json' });
  save(db);

  console.log('');
  console.log(`  已导入角色「${name}」(id=${id})`);
  console.log(`    采用：${Object.keys(found).join(', ')}`);
  if (missing.length) console.log(`    缺失（用占位图补上）：${missing.join(', ')}`);
  if (audioCfg) console.log(`    语音：${audioCfg.file}`);
  console.log(`    切换：node tools/character.js --use ${id}`);
  console.log('');
  process.exit(0);
}

if (has('--set-audio')) {
  const id = opt('--set-audio', '');
  const file = opt('--file', '');
  const db = load();
  const role = db.roles.find((r) => r.id === id);
  if (!role) { console.error(`没有角色 ${id}`); process.exit(2); }
  if (!file || !fs.existsSync(file)) { console.error('音频文件不存在：' + file); process.exit(2); }
  const ext = path.extname(file).toLowerCase();
  if (!AUDIO_EXT.includes(ext)) { console.error(`不支持的音频格式 ${ext}，支持：${AUDIO_EXT.join(' ')}`); process.exit(2); }

  const dir = path.join(charRoot, id, 'audio');
  fs.mkdirSync(dir, { recursive: true });
  const dest = path.join(dir, path.basename(file));
  fs.copyFileSync(file, dest);
  role.audio = role.audio || {};
  role.audio.click = {
    file: `characters/${id}/audio/${path.basename(file)}`.replace(/\\/g, '/'),
    volume: Number(opt('--volume', '0.85')) || 0.85,
    triggerText: opt('--trigger', ''),
  };
  save(db);
  console.log(`  已设置「${role.name}」的点击语音：${role.audio.click.file}`);
  if (role.audio.click.triggerText) console.log(`  只在台词含「${role.audio.click.triggerText}」时播放`);
  else console.log('  每次点击都播放');
  process.exit(0);
}

if (has('--clear-audio')) {
  const id = opt('--clear-audio', '');
  const db = load();
  const role = db.roles.find((r) => r.id === id);
  if (!role) { console.error(`没有角色 ${id}`); process.exit(2); }
  role.audio = { click: null };
  save(db);
  console.log(`  已清除「${role.name}」的语音`);
  process.exit(0);
}

if (has('--remove')) {
  const id = opt('--remove', '');
  const db = load();
  const idx = db.roles.findIndex((r) => r.id === id);
  if (idx < 0) { console.error(`没有角色 ${id}`); process.exit(2); }
  if (db.roles.length === 1) { console.error('至少要保留一个角色'); process.exit(2); }
  const removed = db.roles.splice(idx, 1)[0];
  if (db.defaultRole === id) db.defaultRole = db.roles[0].id;
  save(db);
  console.log(`  已移除「${removed.name}」(${id})；文件没删，仍在 characters/${id}/`);
  process.exit(0);
}

if (has('--check')) {
  const only = opt('--id', '');
  const db = load();
  const list = only ? db.roles.filter((r) => r.id === only) : db.roles;
  if (!list.length) { console.error('没找到角色'); process.exit(2); }
  let bad = 0;
  for (const role of list) {
    const rep = roleReport(role);
    console.log('');
    console.log(`  [${role.id}] ${role.name}${role.id === currentId(db) ? '  (当前)' : ''}`);
    for (const [s, rel, info] of rep.rows) {
      const flag = info === '文件不存在' || info === '未配置' ? '✗' : ' ';
      console.log(`    ${flag} ${s.padEnd(12)} ${String(info).padEnd(16)} ${rel}`);
    }
    console.log(`      语音：${rep.audioInfo}`);
    console.log(`      台词：${rep.personaInfo}`);
    if (rep.issues.length) { bad++; rep.issues.forEach((i) => console.log(`      ⚠ ${i}`)); }
  }
  console.log('');
  console.log(bad ? `  ${bad} 个角色有问题` : '  全部角色通过校验');
  console.log('');
  process.exit(bad ? 1 : 0);
}

console.log('用法：--list | --use <id> | --new <id> | --import <目录> --id <id> | --set-audio <id> --file <音频> | --check | --remove <id>');
