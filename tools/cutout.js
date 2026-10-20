// 桌宠立绘抠图
// 流程：flood fill 外围背景 -> 找被气泡轮廓围住的"洞" -> 从洞向外做深度受限膨胀定出气泡
//       -> 剩下的人物主体用连通域取最大块 -> alpha 腐蚀+羽化 -> 输出 PNG
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const [rawPath, metaPath, outDir, prefix] = process.argv.slice(2);
const meta = JSON.parse(fs.readFileSync(metaPath, 'utf8').replace(/^\uFEFF/, ''));
const { width: w, height: h, stride } = meta;
const buf = fs.readFileSync(rawPath);
const n = w * h;
const WHITE = Number(process.env.WHITE_THRESHOLD || 228);
const DEPTH = Number(process.env.BUBBLE_DEPTH || 12);

const idx = (x, y) => y * stride + x * 4;
const isWhiteAt = (x, y) => {
  const o = idx(x, y);
  return buf[o] >= WHITE && buf[o + 1] >= WHITE && buf[o + 2] >= WHITE;
};

// ---------- 1) 外围背景 ----------
const bg = new Uint8Array(n);
const q0 = [];
const seedBg = (i) => {
  if (bg[i]) return;
  if (!isWhiteAt(i % w, (i / w) | 0)) return;
  bg[i] = 1; q0.push(i);
};
for (let x = 0; x < w; x++) { seedBg(x); seedBg((h - 1) * w + x); }
for (let y = 0; y < h; y++) { seedBg(y * w); seedBg(y * w + w - 1); }
for (let qi = 0; qi < q0.length; qi++) {
  const i = q0[qi], x = i % w, y = (i / w) | 0;
  if (x > 0) seedBg(i - 1);
  if (x < w - 1) seedBg(i + 1);
  if (y > 0) seedBg(i - w);
  if (y < h - 1) seedBg(i + w);
}

const opaque = new Uint8Array(n);
for (let i = 0; i < n; i++) opaque[i] = bg[i] ? 0 : 1;

// ---------- 2) 找"洞"：不是外围背景、但又近白的区域 = 被轮廓围住 ----------
function labelMask(mask) {
  const seen = new Uint8Array(n);
  const out = [];
  for (let i = 0; i < n; i++) {
    if (!mask[i] || seen[i]) continue;
    const st = [i]; seen[i] = 1; const px = [];
    let minX = w, minY = h, maxX = -1, maxY = -1;
    while (st.length) {
      const p = st.pop(); px.push(p);
      const x = p % w, y = (p / w) | 0;
      if (x < minX) minX = x; if (x > maxX) maxX = x;
      if (y < minY) minY = y; if (y > maxY) maxY = y;
      if (x > 0 && mask[p - 1] && !seen[p - 1]) { seen[p - 1] = 1; st.push(p - 1); }
      if (x < w - 1 && mask[p + 1] && !seen[p + 1]) { seen[p + 1] = 1; st.push(p + 1); }
      if (y > 0 && mask[p - w] && !seen[p - w]) { seen[p - w] = 1; st.push(p - w); }
      if (y < h - 1 && mask[p + w] && !seen[p + w]) { seen[p + w] = 1; st.push(p + w); }
    }
    out.push({ px, minX, minY, maxX, maxY, size: px.length });
  }
  out.sort((a, b) => b.size - a.size);
  return out;
}

const enclosedWhite = new Uint8Array(n);
for (let i = 0; i < n; i++) enclosedWhite[i] = (!bg[i] && isWhiteAt(i % w, (i / w) | 0)) ? 1 : 0;
const holes = labelMask(enclosedWhite);
const hole = holes.length ? holes[0] : null;

let bubbleMask = new Uint8Array(n);

// NO_BUBBLE=1：图里没有对话框，跳过"找洞定气泡"这一步，
// 直接把最大的不透明连通块当成人物（表情包素材多是这种）。
const NO_BUBBLE = process.env.NO_BUBBLE === '1';

if (!NO_BUBBLE && hole && hole.size > 500) {
  // ---------- 3) 从洞向外做深度受限膨胀（够覆盖气泡轮廓 ~6px） ----------
  const INF = 1e9;
  const dist = new Int32Array(n).fill(INF);
  const qq = [];
  for (const p of hole.px) {
    const x = p % w, y = (p / w) | 0;
    const nb = [x > 0 ? p - 1 : -1, x < w - 1 ? p + 1 : -1, y > 0 ? p - w : -1, y < h - 1 ? p + w : -1];
    for (const t of nb) {
      if (t < 0 || !opaque[t] || dist[t] <= 1) continue;
      dist[t] = 1; qq.push(t);
    }
  }
  for (let i = 0; i < qq.length; i++) {
    const p = qq[i], d = dist[p];
    if (d >= DEPTH) continue;
    const x = p % w, y = (p / w) | 0;
    const nb = [x > 0 ? p - 1 : -1, x < w - 1 ? p + 1 : -1, y > 0 ? p - w : -1, y < h - 1 ? p + w : -1];
    for (const t of nb) {
      if (t < 0 || !opaque[t] || dist[t] <= d + 1) continue;
      dist[t] = d + 1; qq.push(t);
    }
  }
  for (let i = 0; i < n; i++) if (opaque[i] && dist[i] <= DEPTH) bubbleMask[i] = 1;
}

// ---------- 4) 人物分割 ----------
// 无气泡模式：所有不透明连通块都算人物（只滤掉极小噪点）。
// 这一步很关键——有些素材里角/发饰和头是分开的，只取"最大块"会把角丢掉。
let charMask = new Uint8Array(n);
let splitNote = '';
if (NO_BUBBLE) {
  const comps = labelMask(opaque);
  const MIN_PIECE = 40;
  let kept = 0;
  for (const c of comps) {
    if (c.size < MIN_PIECE) continue;
    kept++;
    for (const p of c.px) charMask[p] = 1;
  }
  splitNote = `无气泡模式：保留 ${kept} 个连通块（>=${MIN_PIECE}px），共 ${comps.length} 块`;
} else {
  const charCand = new Uint8Array(n);
  for (let i = 0; i < n; i++) charCand[i] = (opaque[i] && !bubbleMask[i]) ? 1 : 0;
  const parts = labelMask(charCand);
  splitNote = '（未发现气泡空洞，整图按单一主体处理）';
  if (parts.length) {
    const main = parts[0];
    for (const p of main.px) charMask[p] = 1;
    for (let k = 1; k < parts.length; k++) for (const p of parts[k].px) bubbleMask[p] = 1;
    splitNote = `气泡空洞 ${hole ? hole.size : 0}px，轮廓膨胀 R=${DEPTH}；人物主体 ${main.size}px，其余 ${parts.length - 1} 块归入气泡层`;
  }
}

// 人物 bbox
let minX = w, minY = h, maxX = -1, maxY = -1;
for (let y = 0; y < h; y++) for (let x = 0; x < w; x++)
  if (charMask[y * w + x]) { if (x < minX) minX = x; if (x > maxX) maxX = x; if (y < minY) minY = y; if (y > maxY) maxY = y; }

const restMask = new Uint8Array(n);
for (let i = 0; i < n; i++) restMask[i] = (opaque[i] && !charMask[i]) ? 1 : 0;

// ---------- 5) alpha ----------
function buildAlpha(mask, erode) {
  let a = new Float32Array(n);
  for (let i = 0; i < n; i++) a[i] = mask[i] ? 255 : 0;
  for (let e = 0; e < erode; e++) {
    const b = a.slice();
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
      const i = y * w + x;
      if (a[i] === 0) continue;
      if ((x > 0 && a[i - 1] === 0) || (x < w - 1 && a[i + 1] === 0) ||
          (y > 0 && a[i - w] === 0) || (y < h - 1 && a[i + w] === 0)) b[i] = 0;
    }
    a = b;
  }
  const blur = a.slice();
  for (let y = 1; y < h - 1; y++) for (let x = 1; x < w - 1; x++) {
    const i = y * w + x;
    let s = 0;
    for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) s += a[i + dy * w + dx];
    blur[i] = Math.round(s / 9);
  }
  return blur;
}

// ---------- 6) PNG ----------
function crc32(b) {
  let c, crc = 0xffffffff;
  for (let i = 0; i < b.length; i++) {
    c = (crc ^ b[i]) & 0xff;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    crc = (crc >>> 8) ^ c;
  }
  return (crc ^ 0xffffffff) >>> 0;
}
function chunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
  const t = Buffer.from(type, 'ascii');
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(Buffer.concat([t, data])));
  return Buffer.concat([len, t, data, crc]);
}
function writePNG(file, cw, ch, rgba) {
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(cw, 0); ihdr.writeUInt32BE(ch, 4);
  ihdr[8] = 8; ihdr[9] = 6;
  const raw = Buffer.alloc((cw * 4 + 1) * ch);
  for (let y = 0; y < ch; y++) rgba.copy(raw, y * (cw * 4 + 1) + 1, y * cw * 4, (y + 1) * cw * 4);
  fs.writeFileSync(file, Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw, { level: 9 })), chunk('IEND', Buffer.alloc(0)),
  ]));
}

function layerFile(mask, erode, file) {
  const alpha = buildAlpha(mask, erode);
  const out = Buffer.alloc(n * 4);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const si = idx(x, y), di = (y * w + x) * 4, a = alpha[y * w + x];
    out[di] = buf[si + 2]; out[di + 1] = buf[si + 1]; out[di + 2] = buf[si]; out[di + 3] = a;
  }
  writePNG(file, w, h, out);
}

fs.mkdirSync(outDir, { recursive: true });
const P = (s) => path.join(outDir, `${prefix}-${s}.png`);
layerFile(charMask, 1, P('character'));
layerFile(restMask, 1, P('bubble'));

let trimmed = 'n/a';
{
  const pad = Math.max(6, Math.round((maxX - minX + 1) * 0.03));
  const x0 = Math.max(0, minX - pad), y0 = Math.max(0, minY - pad);
  const x1 = Math.min(w - 1, maxX + pad), y1 = Math.min(h - 1, maxY + pad);
  const cw = x1 - x0 + 1, chh = y1 - y0 + 1;
  const alpha = buildAlpha(charMask, 1);
  const out = Buffer.alloc(cw * chh * 4);
  for (let y = 0; y < chh; y++) for (let x = 0; x < cw; x++) {
    const sx = x0 + x, sy = y0 + y, si = idx(sx, sy), di = (y * cw + x) * 4;
    out[di] = buf[si + 2]; out[di + 1] = buf[si + 1]; out[di + 2] = buf[si];
    out[di + 3] = alpha[sy * w + sx];
  }
  writePNG(P('character-trim'), cw, chh, out);
  trimmed = `${cw}x${chh}`;
}

// 棋盘格预览：人物红框标示
{
  const aC = buildAlpha(charMask, 1), aB = buildAlpha(restMask, 1);
  const out = Buffer.alloc(n * 4);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const si = idx(x, y), di = (y * w + x) * 4;
    const a = Math.max(aC[y * w + x], aB[y * w + x]) / 255;
    const ck = (((x / 16) | 0) + ((y / 16) | 0)) % 2 === 0 ? 205 : 155;
    out[di] = Math.round(buf[si + 2] * a + ck * (1 - a));
    out[di + 1] = Math.round(buf[si + 1] * a + ck * (1 - a));
    out[di + 2] = Math.round(buf[si] * a + ck * (1 - a));
    out[di + 3] = 255;
  }
  writePNG(P('preview'), w, h, out);
}

console.log(`源: ${w}x${h}  WHITE=${WHITE}  DEPTH=${DEPTH}`);
console.log(splitNote);
console.log(`人物 bbox: (${minX},${minY})-(${maxX},${maxY}) = ${maxX - minX + 1}x${maxY - minY + 1}`);
console.log(`裁切: ${trimmed}`);
