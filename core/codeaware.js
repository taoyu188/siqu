/**
 * 祀 · 看懂源码（codeaware）
 * ==================================================================
 * 编译成功之后，再瞄一眼源码里有没有"对她说话"的内容。
 * 目前支持：
 *   - printf/puts 的字符串里叫她（祀 / 管理员 / Si）
 *   - 常见问候（hello / hi / 你好 / 您好）
 *   → 回应「你好，管理员。」
 *
 * 用法：
 *   node core/codeaware.js --file x.c           人读
 *   node core/codeaware.js --file x.c --json    机器读
 *   node core/codeaware.js --file x.c --json --out result.json
 */
const fs = require('fs');
const path = require('path');

const args = process.argv.slice(2);
const opt = (n, d) => { const i = args.indexOf(n); return i >= 0 && args[i + 1] ? args[i + 1] : d; };
const has = (f) => args.includes(f);

const srcFile = opt('--file', null);
const asJson = has('--json');
const outFile = opt('--out', null);

/** 抽出 C 源码里 printf/puts/fputs 的字符串字面量 */
function extractLiterals(code) {
  const lits = [];
  const re = /\b(printf|puts|fputs|sprintf|fprintf)\s*\(([^;]*)\)/g;
  let m;
  while ((m = re.exec(code)) !== null) {
    const inner = m[2];
    const sre = /"((?:[^"\\]|\\.)*)"/g;
    let s;
    while ((s = sre.exec(inner)) !== null) {
      lits.push(s[1].replace(/\\(n|t|\\|")/g, (_, c) => ({ n: '\n', t: '\t', '\\': '\\', '"': '"' }[c])));
    }
  }
  return lits;
}

/**
 * 读源码文件。
 * Dev-C++ 默认按系统代码页保存（中文 Windows = GBK），
 * 直接按 UTF-8 读，"祀"会变成乱码，什么也匹配不到。
 * 所以：先严格试 UTF-8，失败就退回 GBK。
 */
function readSource(file) {
  const buf = fs.readFileSync(file);
  const utf8Strict = new TextDecoder('utf-8', { fatal: true });
  try {
    return { text: utf8Strict.decode(buf), encoding: 'utf-8' };
  } catch (_) { /* 不是合法 UTF-8 */ }
  try {
    return { text: new TextDecoder('gbk').decode(buf), encoding: 'gbk' };
  } catch (_) { /* 环境没有 GBK 解码器 */ }
  // UTF-8 能读但含替换字符，也当作 GBK 再试一次
  const loose = buf.toString('utf8');
  if (loose.includes('\uFFFD')) {
    try { return { text: new TextDecoder('gbk').decode(buf), encoding: 'gbk-guess' }; } catch (_) {}
  }
  return { text: loose, encoding: 'utf-8-loose' };
}

function analyze(file) {
  const { text: code, encoding } = readSource(file);
  const lits = extractLiterals(code);
  const joined = lits.join('\n');

  const result = { file: path.basename(file), kind: 'none', encoding: encoding, literals: lits.slice(0, 10) };

  // 1) 有没有直接叫她（名字 / 称呼）
  const callsHer = /祀|管理员|\bSi\b|\bsiqu\b/i.test(joined);
  // 2) 中文问候才算问候。
  //    注意：不能把英文 hello 当问候——几乎所有入门程序都 printf("hello world")，
  //    那样她每次都会喊"你好管理员"，吵死了。
  const greetsZh = /你好|您好|早上好|晚上好|下午好|好久不见/.test(joined);

  if (callsHer) {
    result.kind = 'called';
    result.say = '……听到了。你好，管理员。';
    result.detail = '你在程序里叫了我的名字。';
  } else if (greetsZh) {
    result.kind = 'greeting';
    result.say = '你好，管理员。';
    result.detail = '程序跑起来会先说这句话——我替它先应了。';
  }

  return result;
}

if (!srcFile) {
  console.error('用法: node codeaware.js --file <源码.c> [--json] [--out 文件]');
  process.exit(2);
}
if (!fs.existsSync(srcFile)) {
  console.error(`找不到源码：${srcFile}`);
  process.exit(2);
}

const res = analyze(srcFile);
const text = JSON.stringify(res, null, 2);

if (asJson) {
  // 和 diagnose 一样：纯 ASCII，避免 PowerShell 用 GBK 解码时把中文拆坏
  const ascii = text.replace(/[\u007f-\uffff]/g, (c) => '\\u' + c.charCodeAt(0).toString(16).padStart(4, '0'));
  if (outFile) fs.writeFileSync(outFile, ascii, 'utf8');
  else console.log(ascii);
} else {
  console.log(`${res.file}: ${res.kind}`);
  if (res.say) console.log(`  祀会回应：「${res.say}」`);
}
