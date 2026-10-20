/**
 * Python 运行包装器
 * ------------------------------------------------------------------
 * 用法（和平时一样跑，只是前面加 node 这个脚本）：
 *   node core/pyrun.js 你的脚本.py [参数...]
 *
 * 做的事：
 *   1. 用 py 启动你的脚本（继承终端，你能看到正常输出）
 *   2. 把 stdout/stderr 同时写进 %USERPROFILE%\.siqu\python.log
 *   3. 退出码透传，脚本行为不受影响
 *
 * 桌宠监视 python.log，一旦有新的 Traceback 就会吐槽并解释。
 */
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

function homeDir() { return process.env.SIQU_HOME || path.join(os.homedir(), '.siqu'); }
const logPath = path.join(homeDir(), 'python.log');

const argv = process.argv.slice(2);
if (!argv.length) {
  console.error('用法: node core/pyrun.js <脚本.py> [参数...]');
  process.exit(2);
}

// 取 Python 解释器：优先 py（Windows 启动器），其次 python
function pickPython() {
  const test = spawnSync('py', ['-c', 'import sys;print(sys.version_info[0])'], { encoding: 'utf8' });
  if (test.status === 0 && test.stdout.trim().startsWith('3')) return 'py';
  const test2 = spawnSync('python', ['-c', 'import sys;print(sys.version_info[0])'], { encoding: 'utf8' });
  if (test2.status === 0 && test2.stdout.trim().startsWith('3')) return 'python';
  return 'py';
}

const python = pickPython();
const script = argv[0];

// 记录一次运行的开始
function marker() {
  const t = new Date().toISOString();
  return `\n=== RUN ${t} :: ${argv.join(' ')} ===\n`;
}

try {
  fs.mkdirSync(homeDir(), { recursive: true });
  fs.appendFileSync(logPath, marker(), 'utf8');
} catch (e) { /* 日志写不了也继续跑 */ }

const child = spawnSync(python, argv, { encoding: 'buffer', stdio: ['inherit', 'pipe', 'pipe'] });

function emitAndLog(chunk, stream) {
  if (!chunk || !chunk.length) return;
  stream.write(chunk);
  try { fs.appendFileSync(logPath, chunk); } catch (e) { /* ignore */ }
}

emitAndLog(child.stdout, process.stdout);
emitAndLog(child.stderr, process.stderr);

// 结束时补一个退出码，方便 pydiag 判断是否成功
try {
  fs.appendFileSync(logPath, `=== EXIT ${child.status === null ? -1 : child.status} ===\n`, 'utf8');
} catch (e) { /* ignore */ }

process.exit(child.status === null ? 1 : child.status);
