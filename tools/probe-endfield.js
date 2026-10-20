/**
 * 终末地数据接口探测（临时工具）
 * 目的是找出哪个 endpoint + 参数组合能返回理智等数据
 */
const path = require('path');
const { loadCred, signHeaders, getBindings, allEndfields } = require(path.join(__dirname, '..', 'core', 'skland.js'));

const BASE = 'https://zonai.skland.com';

async function call(cred, url, method, body, extraHeaders) {
  const headers = { ...signHeaders(cred, url, method || 'get', body), ...(extraHeaders || {}) };
  const init = { method: (method || 'get').toUpperCase(), headers };
  if (method === 'post') {
    headers['Content-Type'] = 'application/json';
    init.body = body === undefined ? '' : JSON.stringify(body);
  }
  try {
    const res = await fetch(url, init);
    const t = await res.text();
    let j;
    try { j = JSON.parse(t); } catch { j = { _raw: t.slice(0, 120) }; }
    return { http: res.status, code: j.code, message: j.message, data: j.data, raw: j };
  } catch (e) {
    return { error: e.message };
  }
}

(async () => {
  const cred = loadCred();
  if (!cred) { console.log('未登录'); return; }
  const bindings = await getBindings(cred);
  const efs = allEndfields(bindings);
  console.log('终末地账号：');
  efs.forEach((e) => console.log(`  uid=${e.uid} server=${e.serverId} ${e.serverName}`));
  const ef = efs[0];
  const role = `3_${ef.uid}_${ef.serverId}`;

  const common = {
    'Accept': 'application/json, text/plain, */*',
    'sk-language': 'zh-cn',
    'Origin': 'https://www.skland.com',
    'Referer': 'https://www.skland.com/',
  };
  const probes = [
    ['H. card/detail + 常用头', `${BASE}/web/v1/game/endfield/card/detail?roleId=${ef.uid}&serverId=${ef.serverId}&userId=${cred.userId}`, { ...common, 'sk-game-role': role }],
    ['I. card/detail + 全头无 role', `${BASE}/web/v1/game/endfield/card/detail?roleId=${ef.uid}&serverId=${ef.serverId}&userId=${cred.userId}`, { ...common }],
    ['J. 官服账号 + 全头', `${BASE}/web/v1/game/endfield/card/detail?roleId=${efs[1].uid}&serverId=${efs[1].serverId}&userId=${cred.userId}`, { ...common, 'sk-game-role': `3_${efs[1].uid}_${efs[1].serverId}` }],
    ['K. card/detail 不带 userId', `${BASE}/web/v1/game/endfield/card/detail?roleId=${ef.uid}&serverId=${ef.serverId}`, { ...common, 'sk-game-role': role }],
    ['L. game/player/info 带 role', `${BASE}/api/v1/game/player/info?uid=${ef.uid}&serverId=${ef.serverId}`, { ...common, 'sk-game-role': role }],
    ['M. web player basic', `${BASE}/web/v1/game/endfield/card/basic?roleId=${ef.uid}&serverId=${ef.serverId}&userId=${cred.userId}`, { ...common, 'sk-game-role': role }],
    ['A. card/detail 原样', `${BASE}/web/v1/game/endfield/card/detail?roleId=${ef.uid}&serverId=${ef.serverId}&userId=${cred.userId}`],
    ['B. card/detail + sk-game-role', `${BASE}/web/v1/game/endfield/card/detail?roleId=${ef.uid}&serverId=${ef.serverId}&userId=${cred.userId}`, { 'sk-game-role': role }],
    ['C. card/detail 参数顺序变', `${BASE}/web/v1/game/endfield/card/detail?userId=${cred.userId}&roleId=${ef.uid}&serverId=${ef.serverId}`, { 'sk-game-role': role }],
    ['D. /api/v1/game/player/info?uid=', `${BASE}/api/v1/game/player/info?uid=${ef.uid}`, { 'sk-game-role': role }],
    ['E. /web/v1/game/endfield/card/base', `${BASE}/web/v1/game/endfield/card/base?roleId=${ef.uid}&serverId=${ef.serverId}&userId=${cred.userId}`, { 'sk-game-role': role }],
    ['F. /web/v1/game/endfield/player/info', `${BASE}/web/v1/game/endfield/player/info?roleId=${ef.uid}&serverId=${ef.serverId}&userId=${cred.userId}`, { 'sk-game-role': role }],
    ['G. attendance(GET 试探)', `${BASE}/web/v1/game/endfield/attendance`, null, { 'sk-game-role': role }],
  ];

  for (const [label, url, extra] of probes) {
    const r = await call(cred, url, 'get', null, extra);
    const head = r.error ? `ERROR ${r.error}` : `http=${r.http} code=${r.code} msg=${(r.message || '').slice(0, 40)}`;
    console.log('');
    console.log(`  ${label}`);
    console.log(`    ${head}`);
    if (r.data && typeof r.data === 'object') {
      const keys = Object.keys(r.data);
      console.log(`    data 字段：${keys.slice(0, 12).join(', ')}${keys.length > 12 ? ' …' : ''}`);
      const flat = JSON.stringify(r.data);
      if (/理智|stamina|sanity|ap\b|energy/i.test(flat)) {
        const m = flat.match(/[^,{]{0,40}(理智|stamina|sanity|energy)[^,}]{0,60}/i);
        console.log(`    ★ 命中关键词：${m ? m[0].slice(0, 100) : ''}`);
      }
    }
  }
})().catch((e) => console.log('探测失败：' + e.message));
