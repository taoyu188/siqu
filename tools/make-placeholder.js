/**
 * 生成占位角色立绘（无第三方依赖）
 * ------------------------------------------------------------------
 * 目的：让别人 clone 下来就能跑，不需要附带任何官方/同人素材。
 * 画一只圆形小生物，8 个表情用颜色 + 眼睛 + 嘴巴区分。
 *
 * 用法：
 *   node tools/make-placeholder.js                    输出到 characters/placeholder/images/
 *   node tools/make-placeholder.js --out <目录>
 *   node tools/make-placeholder.js --size 512 --ss 2
 */
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const appRoot = path.dirname(__dirname);

// ---------------- PNG 写入（RGBA） ----------------
function crc32(buf) {
  const t = [];
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  let crc = 0xffffffff;
  for (let i = 0; i < buf.length; i++) crc = t[(crc ^ buf[i]) & 0xff] ^ (crc >>> 8);
  return (crc ^ 0xffffffff) >>> 0;
}
function chunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length, 0);
  const body = Buffer.concat([Buffer.from(type, 'ascii'), data]);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(body), 0);
  return Buffer.concat([len, body, crc]);
}
function writePng(file, w, h, rgba) {
  const raw = Buffer.alloc((w * 4 + 1) * h);
  for (let y = 0; y < h; y++) {
    raw[y * (w * 4 + 1)] = 0;
    rgba.copy(raw, y * (w * 4 + 1) + 1, y * w * 4, (y + 1) * w * 4);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8; ihdr[9] = 6; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
  const png = Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', zlib.deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, png);
  return png.length;
}

// ---------------- 画布 ----------------
function makeCanvas(size) {
  const buf = Buffer.alloc(size * size * 4, 0);
  const put = (x, y, r, g, b, a) => {
    if (x < 0 || y < 0 || x >= size || y >= size || a <= 0) return;
    const i = (y * size + x) * 4;
    const sa = a / 255;
    const da = buf[i + 3] / 255;
    const oa = sa + da * (1 - sa);
    if (oa <= 0) return;
    buf[i] = Math.round((r * sa + buf[i] * da * (1 - sa)) / oa);
    buf[i + 1] = Math.round((g * sa + buf[i + 1] * da * (1 - sa)) / oa);
    buf[i + 2] = Math.round((b * sa + buf[i + 2] * da * (1 - sa)) / oa);
    buf[i + 3] = Math.round(oa * 255);
  };
  return { size, buf, put };
}

function hexToRgb(hex) {
  const h = hex.replace('#', '');
  return [parseInt(h.slice(0, 2), 16), parseInt(h.slice(2, 4), 16), parseInt(h.slice(4, 6), 16)];
}

/** 椭圆填充（归一化坐标判断，天然抗锯齿边缘靠 ss 采样） */
function ellipse(c, cx, cy, rx, ry, color, alpha = 255) {
  const [r, g, b] = hexToRgb(color);
  const x0 = Math.floor(cx - rx - 1), x1 = Math.ceil(cx + rx + 1);
  const y0 = Math.floor(cy - ry - 1), y1 = Math.ceil(cy + ry + 1);
  for (let y = y0; y <= y1; y++) {
    for (let x = x0; x <= x1; x++) {
      const dx = (x - cx) / rx, dy = (y - cy) / ry;
      if (dx * dx + dy * dy <= 1) c.put(x, y, r, g, b, alpha);
    }
  }
}

/** 圆弧（当嘴巴用），角度用弧度，0 在右，顺时针 */
function arc(c, cx, cy, rx, ry, thickness, color, a0, a1) {
  const [r, g, b] = hexToRgb(color);
  const steps = 400;
  for (let i = 0; i <= steps; i++) {
    const a = a0 + (a1 - a0) * (i / steps);
    const px = cx + Math.cos(a) * rx;
    const py = cy + Math.sin(a) * ry;
    ellipse(c, px, py, thickness / 2, thickness / 2, color);
  }
}

/** 线段（闭眼用） */
function line(c, x0, y0, x1, y1, thickness, color) {
  const dx = x1 - x0, dy = y1 - y0;
  const len = Math.hypot(dx, dy);
  const steps = Math.max(1, Math.ceil(len));
  for (let i = 0; i <= steps; i++) {
    const t = i / steps;
    ellipse(c, x0 + dx * t, y0 + dy * t, thickness / 2, thickness / 2, color);
  }
}

// ---------------- 8 个表情 ----------------
const STATES = [
  { id: 'idle',        body: '#7FB4A0', face: 'smile',  blush: false },
  { id: 'happy',       body: '#6FC08A', face: 'grin',   blush: true  },
  { id: 'taunt',       body: '#D98C8C', face: 'smug',   blush: false },
  { id: 'confused',    body: '#8C9BD9', face: 'wavy',   blush: false },
  { id: 'embarrassed', body: '#E0A0C0', face: 'shy',    blush: true  },
  { id: 'jealous',     body: '#C98CC9', face: 'pout',   blush: false },
  { id: 'pout',        body: '#D9A08C', face: 'angry',  blush: false },
  { id: 'sleep',       body: '#9AA5B1', face: 'closed', blush: false },
];

function draw(state, size) {
  const c = makeCanvas(size);
  const S = size;
  const cx = S / 2, cy = S * 0.56;
  const bodyR = S * 0.30;

  // 身体（一个大圆 + 底部略宽）
  ellipse(c, cx, cy, bodyR, bodyR * 0.98, state.body);
  ellipse(c, cx, cy + bodyR * 0.42, bodyR * 0.82, bodyR * 0.45, state.body);

  // 头顶小芽
  line(c, cx, cy - bodyR * 0.92, cx + S * 0.012, cy - bodyR * 1.22, S * 0.022, '#5E8A78');
  ellipse(c, cx + S * 0.012, cy - bodyR * 1.24, S * 0.022, S * 0.022, '#8FD3B4');

  const eyeY = cy - S * 0.012;
  const eyeDx = bodyR * 0.40;
  const eyeR = S * 0.030;
  const ink = '#25303A';

  switch (state.face) {
    case 'closed':
      line(c, cx - eyeDx - eyeR, eyeY, cx - eyeDx + eyeR, eyeY, S * 0.014, ink);
      line(c, cx + eyeDx - eyeR, eyeY, cx + eyeDx + eyeR, eyeY, S * 0.014, ink);
      arc(c, cx, cy + S * 0.055, S * 0.030, S * 0.020, S * 0.012, ink, Math.PI * 0.15, Math.PI * 0.85);
      break;
    case 'smile':
      ellipse(c, cx - eyeDx, eyeY, eyeR, eyeR * 1.15, ink);
      ellipse(c, cx + eyeDx, eyeY, eyeR, eyeR * 1.15, ink);
      arc(c, cx, cy + S * 0.050, S * 0.052, S * 0.040, S * 0.013, ink, Math.PI * 0.15, Math.PI * 0.85);
      break;
    case 'grin':
      ellipse(c, cx - eyeDx, eyeY - S * 0.004, eyeR, eyeR * 1.25, ink);
      ellipse(c, cx + eyeDx, eyeY - S * 0.004, eyeR, eyeR * 1.25, ink);
      arc(c, cx, cy + S * 0.045, S * 0.070, S * 0.058, S * 0.015, ink, Math.PI * 0.10, Math.PI * 0.90);
      break;
    case 'smug':
      ellipse(c, cx - eyeDx, eyeY + S * 0.004, eyeR * 1.1, eyeR * 0.75, ink);
      ellipse(c, cx + eyeDx, eyeY + S * 0.004, eyeR * 1.1, eyeR * 0.75, ink);
      line(c, cx - S * 0.035, cy + S * 0.072, cx + S * 0.035, cy + S * 0.068, S * 0.013, ink);
      break;
    case 'wavy':
      ellipse(c, cx - eyeDx, eyeY, eyeR * 1.2, eyeR * 1.2, ink);
      ellipse(c, cx + eyeDx, eyeY, eyeR * 0.75, eyeR * 0.75, ink);
      arc(c, cx - S * 0.018, cy + S * 0.070, S * 0.030, S * 0.018, S * 0.012, ink, Math.PI * 1.1, Math.PI * 1.9);
      arc(c, cx + S * 0.018, cy + S * 0.070, S * 0.030, S * 0.018, S * 0.012, ink, 0.1, Math.PI * 0.9);
      break;
    case 'shy':
      arc(c, cx - eyeDx, eyeY, eyeR * 1.1, eyeR * 0.9, S * 0.013, ink, Math.PI * 1.1, Math.PI * 1.9);
      arc(c, cx + eyeDx, eyeY, eyeR * 1.1, eyeR * 0.9, S * 0.013, ink, Math.PI * 1.1, Math.PI * 1.9);
      arc(c, cx, cy + S * 0.052, S * 0.030, S * 0.026, S * 0.012, ink, Math.PI * 0.2, Math.PI * 0.8);
      break;
    case 'angry':
      ellipse(c, cx - eyeDx, eyeY + S * 0.004, eyeR, eyeR * 0.9, ink);
      ellipse(c, cx + eyeDx, eyeY + S * 0.004, eyeR, eyeR * 0.9, ink);
      line(c, cx - eyeDx - eyeR, eyeY - S * 0.030, cx - eyeDx + eyeR, eyeY - S * 0.018, S * 0.012, ink);
      line(c, cx + eyeDx + eyeR, eyeY - S * 0.030, cx + eyeDx - eyeR, eyeY - S * 0.018, S * 0.012, ink);
      arc(c, cx, cy + S * 0.086, S * 0.036, S * 0.024, S * 0.013, ink, Math.PI * 1.15, Math.PI * 1.85);
      break;
    case 'pout':
    default:
      ellipse(c, cx - eyeDx, eyeY, eyeR, eyeR, ink);
      ellipse(c, cx + eyeDx, eyeY, eyeR, eyeR, ink);
      line(c, cx - S * 0.030, cy + S * 0.074, cx + S * 0.030, cy + S * 0.070, S * 0.012, ink);
      break;
  }

  // 腮红
  if (state.blush) {
    ellipse(c, cx - eyeDx - S * 0.020, eyeY + S * 0.050, S * 0.028, S * 0.016, '#F08CA8', 150);
    ellipse(c, cx + eyeDx + S * 0.020, eyeY + S * 0.050, S * 0.028, S * 0.016, '#F08CA8', 150);
  }

  return c;
}

// ---------------- 主流程 ----------------
const args = process.argv.slice(2);
const opt = (n, d) => { const i = args.indexOf(n); return i >= 0 && args[i + 1] ? args[i + 1] : d; };
const size = Number(opt('--size', '512')) || 512;
const ss = Number(opt('--ss', '2')) || 2;
const outDir = opt('--out', path.join(appRoot, 'characters', 'placeholder', 'images'));

fs.mkdirSync(outDir, { recursive: true });
console.log('');
console.log(`  生成占位立绘：${size}x${size}（超采样 ${ss}x）→ ${outDir}`);
console.log('');

for (const st of STATES) {
  // 超采样：画大图再缩小
  const big = draw(st, size * ss);
  const small = Buffer.alloc(size * size * 4, 0);
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      let r = 0, g = 0, b = 0, a = 0;
      for (let dy = 0; dy < ss; dy++) {
        for (let dx = 0; dx < ss; dx++) {
          const i = ((y * ss + dy) * size * ss + (x * ss + dx)) * 4;
          const sa = big.buf[i + 3] / 255;
          r += big.buf[i] * sa; g += big.buf[i + 1] * sa; b += big.buf[i + 2] * sa; a += sa;
        }
      }
      const n = ss * ss;
      const oa = a / n;
      const o = (y * size + x) * 4;
      if (oa > 0) {
        small[o] = Math.round(r / a);
        small[o + 1] = Math.round(g / a);
        small[o + 2] = Math.round(b / a);
        small[o + 3] = Math.round(oa * 255);
      }
    }
  }
  const file = path.join(outDir, `${st.id}.png`);
  const bytes = writePng(file, size, size, small);
  console.log(`  ✓ ${st.id}.png  ${(bytes / 1024).toFixed(1)} KB`);
}

console.log('');
console.log('  完成。这些是可以随代码分发的占位图（不是任何官方的图）。');
console.log('');
