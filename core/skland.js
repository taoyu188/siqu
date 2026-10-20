/**
 * 森空岛（Skland）数据读取 —— 只读
 * ------------------------------------------------------------------
 * 登录一次，之后用保存的凭据读取终末地 / 明日方舟的游戏数据。
 * 不签到、不领奖、不改账号，只查询。
 *
 * 用法：
 *   node core/skland.js --qr                扫码登录（推荐：弹二维码图片，手机扫）
 *   node core/skland.js --login             手机号 + 密码（密码不回显）
 *   node core/skland.js --login --ocr       手机号 + 短信验证码
 *   node core/skland.js --status            本地凭据状态
 *   node core/skland.js --bindings          已绑定的角色
 *   node core/skland.js --endfield          读终末地数据（人读）
 *   node core/skland.js --endfield --dump   导出原始 JSON
 *   node core/skland.js --endfield --all --dump   所有终末地账号都导出
 *   node core/skland.js --logout            删除本地凭据
 *
 * 多个终末地账号（官服 / B服）：
 *   --uid <uid> --server <serverId>   指定账号
 *   --pick <uid>                      把某个 uid 设为默认
 *
 * 凭据保存在 %USERPROFILE%\.siqu\skland.json（只有 token 和 cred，不保存密码）
 *
 * 协议参考（MIT）：
 *   https://github.com/FrostN0v0/nonebot-plugin-skland
 *   https://github.com/ProbiusOfficial/Skland_API
 */
const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const readline = require('readline');
const zlib = require('zlib');
const { spawn } = require('child_process');

const SKLAND_APP_CODE = '4ca99fa6b56cc2ba';
const UA = 'Skland/1.32.1 (com.hypergryph.skland; build:103201004; Android 33; ) Okhttp/4.11.0';
const BASE = 'https://zonai.skland.com';

function homeDir() { return process.env.SIQU_HOME || path.join(os.homedir(), '.siqu'); }
function credPath() { return path.join(homeDir(), 'skland.json'); }

function loadCred() {
  try { return JSON.parse(fs.readFileSync(credPath(), 'utf8').replace(/^\uFEFF/, '')); }
  catch { return null; }
}
function saveCred(c) {
  fs.mkdirSync(homeDir(), { recursive: true });
  fs.writeFileSync(credPath(), JSON.stringify(c, null, 2), 'utf8');
}

// ---------------- 签名 ----------------
function signHeaders(cred, url, method, body) {
  const timestamp = Math.floor(Date.now() / 1000) - 1;
  const u = new URL(url);
  // 键顺序必须与协议一致：platform -> timestamp -> dId -> vName
  const headerCa = { platform: '', timestamp: String(timestamp), dId: '', vName: '' };
  const headerCaStr = JSON.stringify(headerCa);
  const query = method === 'post'
    ? (body === undefined || body === null ? '' : JSON.stringify(body))
    : u.search.replace(/^\?/, '');
  const secret = `${u.pathname}${query}${timestamp}${headerCaStr}`;
  const hex = crypto.createHmac('sha256', cred.credToken).update(secret, 'utf8').digest('hex');
  const signature = crypto.createHash('md5').update(hex, 'utf8').digest('hex');
  return {
    cred: cred.cred,
    sign: signature,
    platform: '',
    timestamp: String(timestamp),
    dId: '',
    vName: '',
    'User-Agent': UA,
    'Accept-Encoding': 'gzip',
  };
}

async function sklandRequest(cred, url, opts) {
  const method = (opts && opts.method) || 'get';
  const body = opts && opts.body;
  const extra = (opts && opts.headers) || {};
  const headers = { ...signHeaders(cred, url, method, body), ...extra };
  const init = { method: method.toUpperCase(), headers };
  if (method === 'post') {
    headers['Content-Type'] = 'application/json';
    init.body = body === undefined ? '' : JSON.stringify(body);
  }
  const res = await fetch(url, init);
  const text = await res.text();
  let json;
  try { json = JSON.parse(text); }
  catch { throw new Error(`返回不是 JSON（HTTP ${res.status}）：${text.slice(0, 200)}`); }
  if (json.code !== undefined && json.code !== 0) {
    const authHint = /cred|auth|login|token/i.test(String(json.message || ''));
    throw new Error(`接口报错 code=${json.code}: ${json.message || ''}${authHint ? '（凭据可能失效，重新 --qr）' : ''}`);
  }
  return json;
}

// ---------------- 二维码 PNG（手写，无第三方依赖） ----------------
function crc32(buf) {
  const table = [];
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    table[n] = c >>> 0;
  }
  let crc = 0xffffffff;
  for (let i = 0; i < buf.length; i++) crc = table[(crc ^ buf[i]) & 0xff] ^ (crc >>> 8);
  return (crc ^ 0xffffffff) >>> 0;
}

function pngChunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length, 0);
  const body = Buffer.concat([Buffer.from(type, 'ascii'), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body), 0);
  return Buffer.concat([len, body, crc]);
}

function writeQrPng(text, file, scale, quiet) {
  scale = scale || 8;
  quiet = quiet === undefined ? 4 : quiet;
  const QRCode = require(path.join(__dirname, '..', 'vendor', 'qrcode', 'index.js'));
  const qr = new QRCode(-1, 1);
  qr.addData(text);
  qr.make();
  const n = qr.getModuleCount();
  const size = (n + quiet * 2) * scale;
  const rowBytes = Math.ceil(size / 8);
  const rows = [];
  for (let y = 0; y < size; y++) {
    const row = Buffer.alloc(rowBytes + 1, 0);
    const my = Math.floor(y / scale) - quiet;
    for (let x = 0; x < size; x++) {
      const mx = Math.floor(x / scale) - quiet;
      let white = 1;
      if (mx >= 0 && mx < n && my >= 0 && my < n) white = qr.isDark(my, mx) ? 0 : 1;
      if (white) row[1 + (x >> 3)] |= 0x80 >> (x & 7);
    }
    rows.push(row);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(size, 0);
  ihdr.writeUInt32BE(size, 4);
  ihdr[8] = 1; ihdr[9] = 0; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
  const png = Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    pngChunk('IHDR', ihdr),
    pngChunk('IDAT', zlib.deflateSync(Buffer.concat(rows))),
    pngChunk('IEND', Buffer.alloc(0)),
  ]);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, png);
  return { file, size, modules: n };
}

// ---------------- 交互输入 ----------------
function ask(question, opts) {
  const hidden = !!(opts && opts.hidden);
  return new Promise((resolve) => {
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout, terminal: true });
    if (!hidden) {
      rl.question(question, (a) => { rl.close(); resolve(String(a).trim()); });
      return;
    }
    const onData = (ch) => { if (/[\r\n]/.test(ch.toString())) process.stdin.removeListener('data', onData); };
    process.stdin.on('data', onData);
    rl.question(question, (a) => {
      process.stdin.removeListener('data', onData);
      rl.close();
      process.stdout.write('\n');
      resolve(String(a).trim());
    });
  });
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ---------------- 登录 ----------------
async function tokenByPassword(phone, password) {
  const res = await fetch('https://as.hypergryph.com/user/auth/v1/token_by_phone_password', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'User-Agent': UA },
    body: JSON.stringify({ phone, password }),
  });
  const j = await res.json();
  if (j.status !== 0) throw new Error(`登录失败：${j.msg || JSON.stringify(j)}`);
  return j.data.token;
}

async function tokenByCode(phone) {
  let res = await fetch('https://as.hypergryph.com/general/v1/send_phone_code', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'User-Agent': UA },
    body: JSON.stringify({ phone, type: 2 }),
  });
  let j = await res.json();
  if (j.status !== 0) throw new Error(`发送验证码失败：${j.msg || JSON.stringify(j)}`);
  const code = await ask('短信验证码: ');
  res = await fetch('https://as.hypergryph.com/user/auth/v2/token_by_phone_code', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'User-Agent': UA },
    body: JSON.stringify({ phone, code }),
  });
  j = await res.json();
  if (j.status !== 0) throw new Error(`验证码登录失败：${j.msg || JSON.stringify(j)}`);
  return j.data.token;
}

/** token -> 授权码 -> cred -> 保存 */
async function completeLogin(token, method) {
  let res = await fetch('https://as.hypergryph.com/user/oauth2/v2/grant', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'User-Agent': UA },
    body: JSON.stringify({ appCode: SKLAND_APP_CODE, token, type: 0 }),
  });
  let j = await res.json();
  if (j.status !== 0) throw new Error(`换取授权码失败：${j.msg || JSON.stringify(j)}`);

  res = await fetch(`${BASE}/api/v1/user/auth/generate_cred_by_code`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'User-Agent': UA },
    body: JSON.stringify({ code: j.data.code, kind: 1 }),
  });
  j = await res.json();
  if (j.code !== 0) throw new Error(`获取 cred 失败：${j.message || JSON.stringify(j)}`);

  const prev = loadCred() || {};
  const cred = {
    token,
    cred: j.data.cred,
    credToken: j.data.token,
    userId: j.data.userId,
    method: method || 'unknown',
    savedAt: new Date().toISOString(),
    endfieldUid: prev.endfieldUid || null,
    phone: prev.phone || null,
  };
  saveCred(cred);
  console.log('');
  console.log('  登录成功，凭据已保存');
  console.log('  下一步：node core/skland.js --bindings');
  console.log('');
  return cred;
}

async function doQrLogin() {
  let qrlib = null;
  try { qrlib = require(path.join(__dirname, '..', 'vendor', 'qrcode', 'main.js')); } catch { }

  console.log('');
  console.log('  正在创建扫码会话…');
  const res = await fetch('https://as.hypergryph.com/general/v1/gen_scan/login', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'User-Agent': UA },
    body: JSON.stringify({ appCode: SKLAND_APP_CODE }),
  });
  const j = await res.json();
  if (j.status !== 0) throw new Error(`创建扫码会话失败：${j.msg || JSON.stringify(j)}`);

  const scanId = j.data.scanId;
  const scanUrl = j.data.scanUrl || `hypergryph://scan_login?scanId=${scanId}`;

  // 1) 大图（推荐）
  try {
    const qrFile = path.join(homeDir(), 'skland-qr.png');
    const info = writeQrPng(scanUrl, qrFile);
    console.log('');
    console.log(`  二维码图片：${qrFile}（${info.size}x${info.size}）`);
    try {
      spawn('cmd', ['/c', 'start', '', qrFile], { detached: true, stdio: 'ignore' }).unref();
      console.log('  已自动打开，用手机「森空岛」App 扫它，然后在手机上点确认');
    } catch {
      console.log('  （自动打开失败，请手动打开上面的图片）');
    }
  } catch (e) {
    console.log('  生成图片失败：' + e.message);
  }

  // 2) 终端备用
  if (qrlib) {
    console.log('');
    console.log('  或者扫终端里的：');
    console.log('');
    await new Promise((resolve) => {
      qrlib.generate(scanUrl, { small: true }, (out) => {
        console.log(out.split('\n').filter(Boolean).map((l) => '    ' + l).join('\n'));
        resolve();
      });
    });
  }

  console.log('');
  console.log(`  二维码内容：${scanUrl}`);
  console.log('');
  console.log('  等待扫码…（最多 3 分钟，Ctrl+C 取消）');

  for (let i = 0; i < 90; i++) {
    await sleep(2000);
    let st;
    try {
      const r = await fetch(`https://as.hypergryph.com/general/v1/scan_status?scanId=${encodeURIComponent(scanId)}`, {
        headers: { 'User-Agent': UA },
      });
      st = await r.json();
    } catch {
      process.stdout.write('.');
      continue;
    }
    if (st.status === 0 && st.data && st.data.scanCode) {
      console.log('');
      console.log('  已确认，正在换取凭据…');
      const tr = await fetch('https://as.hypergryph.com/user/auth/v1/token_by_scan_code', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'User-Agent': UA },
        body: JSON.stringify({ scanCode: st.data.scanCode }),
      });
      const tj = await tr.json();
      if (tj.status !== 0) throw new Error(`换取 token 失败：${tj.msg || JSON.stringify(tj)}`);
      await completeLogin(tj.data.token, 'qr');
      return;
    }
    const msg = String(st.msg || '');
    if (/过期|失效|expire|invalid/i.test(msg)) throw new Error('二维码已过期，重新运行 --qr');
    process.stdout.write('.');
  }
  throw new Error('等待超时（3 分钟），重新运行 --qr');
}

async function doLogin(useCode) {
  console.log('');
  console.log('  森空岛登录（只读：只保存凭据，不保存密码）');
  console.log('');
  const phone = await ask('手机号: ');
  if (!/^\d{11}$/.test(phone)) { console.error('手机号格式不对'); process.exit(2); }
  const token = useCode
    ? await tokenByCode(phone)
    : await tokenByPassword(phone, await ask('密码（不回显）: ', { hidden: true }));
  const cred = await completeLogin(token, useCode ? 'sms' : 'password');
  cred.phone = phone.slice(0, 3) + '****' + phone.slice(-4);
  saveCred(cred);
}

// ---------------- 数据 ----------------
async function getBindings(cred) {
  const j = await sklandRequest(cred, `${BASE}/api/v1/game/player/binding`, { method: 'get' });
  return (j.data && j.data.list) || [];
}

function allEndfields(bindings) {
  const out = [];
  for (const app of bindings) {
    const code = String(app.appCode || '').toLowerCase();
    const name = String(app.appName || '');
    if (!(code.includes('endfield') || name.includes('终末地'))) continue;
    for (const b of app.bindingList || []) {
      const roles = Array.isArray(b.roles) ? b.roles : [];
      if (roles.length) {
        // 有角色列表：每个角色单独一条（roleId 才是接口要的 roleId）
        for (const r of roles) {
          out.push({
            appCode: app.appCode,
            appName: app.appName,
            uid: String(b.uid),
            roleId: String(r.roleId),
            serverId: String(r.serverId),
            serverType: r.serverType || '',
            serverName: b.channelName || '',
            nickName: r.nickname || b.nickName || '',
            level: r.level || null,
            isDefault: !!r.isDefault || !!b.isDefault,
          });
        }
      } else {
        // 没有角色列表（例如未创建的服）：退回 uid
        out.push({
          appCode: app.appCode,
          appName: app.appName,
          uid: String(b.uid),
          roleId: String(b.uid),
          serverId: String(b.channelMasterId),
          serverType: '',
          serverName: b.channelName || '',
          nickName: b.nickName || '',
          level: null,
          noRole: true,
          isDefault: !!b.isDefault,
        });
      }
    }
  }
  return out;
}

async function getEndfieldCard(cred, ef) {
  const roleId = ef.roleId || ef.uid;
  const url = `${BASE}/web/v1/game/endfield/card/detail`
    + `?roleId=${encodeURIComponent(roleId)}`
    + `&serverId=${encodeURIComponent(ef.serverId)}`
    + `&userId=${encodeURIComponent(cred.userId)}`;
  const j = await sklandRequest(cred, url, {
    method: 'get',
    headers: { 'sk-game-role': `3_${roleId}_${ef.serverId}` },
  });
  const d = j.data && j.data.detail ? j.data.detail : j.data;
  // 顺手把关键字段摘出来，方便上层直接用
  const dn = (d && d.dungeon) || {};
  const cur = Number(dn.curStamina);
  const max = Number(dn.maxStamina);
  const maxTs = Number(dn.maxTs);
  const nowTs = Number((d && d.currentTs) || Math.floor(Date.now() / 1000));
  const stamina = (Number.isFinite(cur) && Number.isFinite(max)) ? {
    current: cur,
    max,
    maxTs: Number.isFinite(maxTs) ? maxTs : null,
    fullInSeconds: Number.isFinite(maxTs) ? Math.max(0, maxTs - nowTs) : null,
    minutesPerPoint: (Number.isFinite(maxTs) && max > cur) ? ((maxTs - nowTs) / 60) / (max - cur) : null,
  } : null;
  return {
    detail: d,
    summary: {
      roleId,
      serverId: ef.serverId,
      nickName: ef.nickName || ((d && d.base && d.base.name) || ''),
      level: (d && d.base && d.base.level) || ef.level || null,
      worldLevel: (d && d.base && d.base.worldLevel) || null,
      stamina,
      daily: (d && d.dailyMission) || null,
      weekly: (d && d.weeklyMission) || null,
      currentTs: nowTs,
    },
  };
}

// ---------------- CLI ----------------
const args = process.argv.slice(2);
const has = (f) => args.includes(f);
const opt = (n, d) => { const i = args.indexOf(n); return i >= 0 && args[i + 1] ? args[i + 1] : d; };

async function cli() {
  if (has('--logout')) {
    if (fs.existsSync(credPath())) { fs.unlinkSync(credPath()); console.log('已删除本地凭据'); }
    else console.log('本来就没有凭据');
    return;
  }

  if (has('--qr') || has('--scan')) { await doQrLogin(); return; }
  if (has('--login')) { await doLogin(has('--ocr')); return; }

  const cred = loadCred();

  if (has('--status')) {
    console.log('');
    if (!cred) {
      console.log('  还没有登录。运行：node core/skland.js --qr');
    } else {
      console.log(`  登录方式：${cred.method || '(未知)'}`);
      console.log(`  森空岛用户 ID：${cred.userId}`);
      console.log(`  保存时间：${cred.savedAt}`);
      if (cred.endfieldUid) console.log(`  默认终末地账号：${cred.endfieldUid}`);
      console.log(`  凭据文件：${credPath()}`);
    }
    console.log('');
    return;
  }

  if (!cred) {
    console.error('还没有登录。先运行：node core/skland.js --qr');
    process.exit(2);
  }

  if (has('--pick')) {
    const uid = opt('--pick', '');
    cred.endfieldUid = uid || null;
    saveCred(cred);
    console.log(`  默认终末地账号已设为：${cred.endfieldUid || '(清除)'}`);
    return;
  }

  if (has('--bindings')) {
    const list = await getBindings(cred);
    console.log('');
    if (!list.length) { console.log('  没有绑定任何角色'); return; }
    for (const app of list) {
      console.log(`  ${app.appName || app.appCode}  (${app.appCode})`);
      for (const b of app.bindingList || []) {
        const mark = String(b.uid) === String(cred.endfieldUid) ? '  <- 默认' : '';
        console.log(`     · ${b.nickName || '(未命名)'}  uid=${b.uid}  服务器=${b.channelName}(${b.channelMasterId})${mark}`);
      }
    }
    console.log('');
    return;
  }

  if (has('--endfield')) {
    const bindings = await getBindings(cred);
    const all = allEndfields(bindings);
    if (!all.length) { console.error('没找到终末地角色（森空岛里要先绑定终末地）'); process.exit(3); }

    const wantUid = opt('--uid', '');
    const wantRole = opt('--role', '');
    const wantServer = opt('--server', '');
    let targets = all;
    if (wantUid) targets = targets.filter((e) => e.uid === String(wantUid));
    if (wantRole) targets = targets.filter((e) => e.roleId === String(wantRole));
    if (wantServer) targets = targets.filter((e) => e.serverId === String(wantServer));
    if (!targets.length) {
      console.error('没有匹配的账号，已有：');
      all.forEach((e) => console.error(`  uid=${e.uid} roleId=${e.roleId} server=${e.serverId} ${e.serverName} ${e.nickName}`));
      process.exit(3);
    }
    if (targets.length > 1 && !has('--all') && !wantRole && !wantUid) {
      const saved = cred.endfieldRoleId ? targets.find((e) => e.roleId === String(cred.endfieldRoleId)) : null;
      targets = [saved || targets.find((e) => e.isDefault) || targets[0]];
    }

    const out = opt('--out', '');
    const isRaw = has('--raw') || has('--dump');
    const wantJson = has('--json');
    let anyOk = false;

    for (const ef of targets) {
      let res = null, error = null;
      try { res = await getEndfieldCard(cred, ef); anyOk = true; }
      catch (e) { error = e.message; }

      if (error) {
        console.log('');
        console.log(`  读取失败 ${ef.nickName || ef.uid}（${ef.serverName}）：${error}`);
        continue;
      }

      if (isRaw) {
        const target = (out && targets.length === 1)
          ? out
          : path.join(homeDir(), `endfield-${ef.roleId}-${ef.serverId}.json`);
        fs.mkdirSync(path.dirname(target), { recursive: true });
        fs.writeFileSync(target, JSON.stringify(res.detail, null, 2), 'utf8');
        console.log('');
        console.log(`  ✓ ${ef.nickName || ef.uid}  ${ef.serverName}  → ${target}`);
        continue;
      }

      if (wantJson) {
        const s = JSON.stringify({ account: ef, fetchedAt: new Date().toISOString(), summary: res.summary }, null, 2);
        if (out && targets.length === 1) fs.writeFileSync(out, s, 'utf8');
        else console.log(s);
        continue;
      }

      const s = res.summary;
      console.log('');
      console.log(`  ${s.nickName}  Lv.${s.level}  世界等级 ${s.worldLevel}  ${ef.serverName}`);
      if (s.stamina) {
        const st = s.stamina;
        console.log(`  ${'理智'.padEnd(6)} ${st.current} / ${st.max}`);
        if (st.fullInSeconds !== null) {
          const h = Math.floor(st.fullInSeconds / 3600);
          const m = Math.floor((st.fullInSeconds % 3600) / 60);
          console.log(`  ${''.padEnd(6)} 距回满 ${h} 小时 ${m} 分`);
        }
        if (st.minutesPerPoint) console.log(`  ${''.padEnd(6)} 回速 ${st.minutesPerPoint.toFixed(2)} 分钟/点`);
      }
      if (s.daily) console.log(`  每日活跃 ${s.daily.dailyActivation} / ${s.daily.maxDailyActivation}`);
      if (s.weekly) console.log(`  每周进度 ${s.weekly.score} / ${s.weekly.total}`);
    }
    if (!isRaw && !wantJson) console.log('');
    if (!anyOk) process.exit(4);
    return;
  }
  console.log('用法：--qr | --login [--ocr] | --status | --bindings | --endfield [--uid X] [--server Y] [--all] [--json|--raw|--dump] [--out f] | --pick UID | --logout');
}

module.exports = {
  loadCred, saveCred, signHeaders, sklandRequest,
  getBindings, allEndfields, getEndfieldCard, homeDir, credPath,
};

if (require.main === module) {
  cli().catch((e) => { console.error('错误：' + e.message); process.exit(1); });
}
