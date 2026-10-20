/**
 * 通过 GitHub API 推送仓库
 * ------------------------------------------------------------------
 * 用途：当 github.com 打不开、但 api.github.com 能通时，用 REST API 完成推送。
 *
 * 用法：
 *   node tools/push-github.js                      交互式
 *   node tools/push-github.js --repo owner/name    跳过仓库名输入
 *   node tools/push-github.js --dry                只列出要上传的文件
 *
 * 需要：classic token（勾 repo）或 fine-grained token（Contents: Read & Write）
 *
 * 原理：Git Data API —— blob → tree → commit → 更新 ref。
 * 空仓库会先用 Contents API 播种一个提交（否则建 blob 会 409）。
 */
const fs = require('fs');
const path = require('path');
const https = require('https');
const readline = require('readline');
const { spawnSync } = require('child_process');

const appRoot = path.dirname(__dirname);
const API_HOST = 'api.github.com';

// ---------------- 命令行参数 ----------------
const argv = process.argv.slice(2);
function flag(name, def) {
  const i = argv.indexOf(name);
  return i >= 0 && argv[i + 1] ? argv[i + 1] : def;
}
const DRY = argv.includes('--dry');
const BRANCH_ARG = flag('--branch', '');
let repoArg = flag('--repo', '');

// ---------------- 交互 ----------------
function ask(question) {
  return new Promise((resolve) => {
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout, terminal: true });
    rl.question(question, (a) => { rl.close(); resolve(String(a).trim()); });
  });
}

/** 隐藏输入：raw mode，按键不回显 */
function askHidden(question) {
  return new Promise((resolve) => {
    process.stdout.write(question);
    const stdin = process.stdin;
    stdin.resume();
    if (stdin.isTTY) stdin.setRawMode(true);
    let buf = '';
    const finish = () => {
      try { if (stdin.isTTY) stdin.setRawMode(false); } catch (e) { /* ignore */ }
      stdin.pause();
      stdin.removeListener('data', onData);
      process.stdout.write('\n');
      resolve(buf.trim());
    };
    const onData = (chunk) => {
      const s = chunk.toString('utf8');
      for (const c of s) {
        if (c === '\r' || c === '\n') { finish(); return; }
        if (c === '\u0003') { process.stdout.write('\n'); process.exit(130); }
        if (c === '\u007f' || c === '\b') { buf = buf.slice(0, -1); continue; }
        buf += c;
      }
    };
    stdin.on('data', onData);
  });
}

// ---------------- HTTP ----------------
function api(token, method, urlPath, body) {
  return new Promise((resolve, reject) => {
    const data = body === undefined ? null : Buffer.from(JSON.stringify(body), 'utf8');
    const req = https.request({
      hostname: API_HOST,
      path: urlPath,
      method: method,
      headers: Object.assign({
        'User-Agent': 'siqu-push/1.1',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'Authorization': 'Bearer ' + token,
      }, data ? { 'Content-Type': 'application/json', 'Content-Length': data.length } : {}),
    }, (res) => {
      let raw = '';
      res.setEncoding('utf8');
      res.on('data', (c) => { raw += c; });
      res.on('end', () => {
        let json = null;
        try { json = raw ? JSON.parse(raw) : null; } catch (e) { /* 非 JSON */ }
        if (res.statusCode >= 200 && res.statusCode < 300) { resolve(json); return; }
        const msg = (json && json.message) || raw.slice(0, 300);
        const err = new Error('HTTP ' + res.statusCode + ' ' + method + ' ' + urlPath + '\n' + msg);
        err.status = res.statusCode;
        reject(err);
      });
    });
    req.on('error', reject);
    if (data) req.write(data);
    req.end();
  });
}

// ---------------- 本地 git ----------------
function findGit() {
  const candidates = [
    process.env.SIQU_GIT,
    'git',
    path.join(path.dirname(appRoot), 'tools', 'mingit', 'cmd', 'git.exe'),
    'C:\\Program Files\\Git\\cmd\\git.exe',
  ].filter(Boolean);
  for (const c of candidates) {
    const r = spawnSync(c, ['--version'], { encoding: 'utf8' });
    if (r.status === 0) return c;
  }
  return null;
}

function listTracked(git) {
  const r = spawnSync(git, ['ls-files', '-z'], { cwd: appRoot, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  if (r.status !== 0) throw new Error('git ls-files 失败：' + (r.stderr || ''));
  return r.stdout.split('\0').filter(Boolean);
}

// ---------------- 主流程 ----------------
(async () => {
  console.log('');
  console.log('  通过 GitHub API 推送');
  console.log('  （不需要能打开 github.com，只要 api.github.com 通）');
  console.log('');

  const git = findGit();
  if (!git) { console.error('  找不到 git，无法确定文件列表。'); process.exit(2); }

  if (!repoArg) {
    repoArg = await ask('  仓库（owner/name，如 taoyu188/siqu）: ');
  }
  if (!/^[\w.-]+\/[\w.-]+$/.test(repoArg)) {
    console.error('  格式不对，应该是 owner/name');
    process.exit(2);
  }
  const parts = repoArg.split('/');
  const owner = parts[0];
  const repo = parts[1];

  // 1) 先看本地要传什么（--dry 在这里结束，不需要 token）
  const files = listTracked(git);
  let totalBytes = 0;
  for (const f of files) {
    try { totalBytes += fs.statSync(path.join(appRoot, f)).size; } catch (e) { /* 忽略 */ }
  }
  console.log('  · 待上传 ' + files.length + ' 个文件');
  console.log('  · 总计 ' + (totalBytes / 1024 / 1024).toFixed(2) + ' MB');

  if (DRY) {
    console.log('');
    files.forEach((f) => console.log('    ' + f));
    console.log('');
    console.log('  （--dry：没有上传）');
    return;
  }

  // 2) 要 token 了
  const token = process.env.GITHUB_TOKEN || await askHidden('  Token（输入不回显，粘贴后回车）: ');
  if (!token) { console.error('  没有 token'); process.exit(2); }

  // 3) 检查仓库
  console.log('');
  console.log('  检查仓库…');
  let repoInfo;
  try {
    repoInfo = await api(token, 'GET', '/repos/' + owner + '/' + repo);
  } catch (e) {
    if (e.status === 404) {
      console.error('  ✗ 仓库不存在：' + owner + '/' + repo);
      console.error('    请先在网页上创建（不要勾 README / .gitignore / license）');
    } else if (e.status === 401) {
      console.error('  ✗ Token 无效或已过期');
    } else {
      console.error('  ✗ ' + e.message);
    }
    process.exit(3);
  }
  const branch = BRANCH_ARG || repoInfo.default_branch || 'main';
  console.log('  ✓ 仓库存在，默认分支 ' + branch + '，可见性 ' + (repoInfo.private ? '私有' : '公开'));

  // 4) 取当前 HEAD；空仓库先播种
  let parentSha = null;
  let baseTree = null;
  try {
    const ref = await api(token, 'GET', '/repos/' + owner + '/' + repo + '/git/ref/heads/' + branch);
    parentSha = ref.object.sha;
    const commit = await api(token, 'GET', '/repos/' + owner + '/' + repo + '/git/commits/' + parentSha);
    baseTree = commit.tree.sha;
    console.log('  ✓ 已有提交 ' + parentSha.slice(0, 7) + '，将基于它更新');
  } catch (e) {
    // 空仓库：GET ref 可能返回 404 或 409（Git Repository is empty）
    if (e.status !== 404 && e.status !== 409) throw e;
    console.log('  · 仓库是空的，先播种一个初始提交…');
    const seedPath = '.gitignore';
    const seedFile = path.join(appRoot, seedPath);
    if (!fs.existsSync(seedFile)) throw new Error('缺少 .gitignore，无法播种');
    await api(token, 'PUT', '/repos/' + owner + '/' + repo + '/contents/' + seedPath, {
      message: 'initialize repository',
      content: fs.readFileSync(seedFile).toString('base64'),
    });
    const ref2 = await api(token, 'GET', '/repos/' + owner + '/' + repo + '/git/ref/heads/' + branch);
    parentSha = ref2.object.sha;
    const commit2 = await api(token, 'GET', '/repos/' + owner + '/' + repo + '/git/commits/' + parentSha);
    baseTree = commit2.tree.sha;
    console.log('  ✓ 播种完成 ' + parentSha.slice(0, 7));
  }

  // 5) 逐个建 blob
  console.log('');
  const tree = [];
  let done = 0;
  for (const f of files) {
    const full = path.join(appRoot, f);
    const blob = await api(token, 'POST', '/repos/' + owner + '/' + repo + '/git/blobs', {
      encoding: 'base64',
      content: fs.readFileSync(full).toString('base64'),
    });
    tree.push({ path: f.split(path.sep).join('/'), mode: '100644', type: 'blob', sha: blob.sha });
    done++;
    const label = f.length > 48 ? f.slice(0, 45) + '...' : f;
    process.stdout.write('\r  上传 ' + done + '/' + files.length + '  ' + label + '        ');
  }
  console.log('');

  // 6) tree → commit → ref
  console.log('  生成目录树…');
  const treeBody = { tree: tree };
  if (baseTree) treeBody.base_tree = baseTree;
  const newTree = await api(token, 'POST', '/repos/' + owner + '/' + repo + '/git/trees', treeBody);

  const message = '祀 · 终末地桌面宠物 v1.0\n\n' + files.length + ' 个文件';
  const commitBody = { message: message, tree: newTree.sha };
  if (parentSha) commitBody.parents = [parentSha];
  const newCommit = await api(token, 'POST', '/repos/' + owner + '/' + repo + '/git/commits', commitBody);
  console.log('  ✓ 提交已创建 ' + newCommit.sha.slice(0, 7));

  if (parentSha) {
    await api(token, 'PATCH', '/repos/' + owner + '/' + repo + '/git/refs/heads/' + branch, {
      sha: newCommit.sha,
      force: false,
    });
  } else {
    await api(token, 'POST', '/repos/' + owner + '/' + repo + '/git/refs', {
      ref: 'refs/heads/' + branch,
      sha: newCommit.sha,
    });
  }

  console.log('');
  console.log('  ✅ 推送完成');
  console.log('     https://github.com/' + owner + '/' + repo);
  console.log('');
})().catch((e) => {
  console.error('');
  console.error('  失败：' + e.message);
  console.error('');
  if (e.status === 401) console.error('  提示：token 可能已撤销或过期，重新生成一个。');
  if (e.status === 403) console.error('  提示：token 权限不足，classic token 要勾 repo。');
  process.exit(1);
});
