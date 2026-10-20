/**
 * 把生成的题目批次合并进题库，并做结构校验
 * ------------------------------------------------------------------
 * 用法：
 *   node tools/merge-questions.js --file textbook\generated\batch1.json
 *   node tools/merge-questions.js --file ... --dry     只校验不写入
 *   node tools/merge-questions.js --file ... --bank custom.json
 *
 * 校验项：
 *   - id 唯一（跨批次、与已有题库都不冲突）
 *   - mcq：必须有 4 个选项，answer 是 0..3 的整数，explain 非空
 *   - code：必须有 statement、solution；io/explain 建议有
 *   - 题目文本长度合理（防止 OCR 垃圾或空题）
 */
const fs = require('fs');
const path = require('path');

const args = process.argv.slice(2);
const opt = (n, d) => { const i = args.indexOf(n); return i >= 0 && args[i + 1] ? args[i + 1] : d; };
const has = (f) => args.includes(f);

const here = __dirname;
const appRoot = path.dirname(here);
const bankPath = opt('--bank', path.join(appRoot, 'core', 'questions.json'));
const batchPath = opt('--file', '');
const dry = has('--dry');

if (!batchPath || !fs.existsSync(batchPath)) {
  console.error('用法: node merge-questions.js --file <批次.json> [--dry] [--bank <题库.json>]');
  process.exit(2);
}

const bank = JSON.parse(fs.readFileSync(bankPath, 'utf8').replace(/^\uFEFF/, ''));
const batch = JSON.parse(fs.readFileSync(batchPath, 'utf8').replace(/^\uFEFF/, ''));
const incoming = batch.questions || [];

const existing = new Set((bank.questions || []).map((q) => q.id));
const problems = [];
const accepted = [];
const seen = new Set();

for (const q of incoming) {
  const id = q.id || '(无 id)';
  const errs = [];

  if (!q.id) errs.push('缺少 id');
  else if (existing.has(q.id)) errs.push(`id 与已有题库冲突：${q.id}`);
  else if (seen.has(q.id)) errs.push(`本批次内 id 重复：${q.id}`);

  const type = q.type || 'mcq';
  if (type === 'mcq') {
    if (!Array.isArray(q.options) || q.options.length !== 4) errs.push('选择题必须有 4 个选项');
    if (typeof q.answer !== 'number' || q.answer < 0 || q.answer > 3) errs.push('answer 必须是 0..3');
    if (!q.q || q.q.length < 6) errs.push('题干太短或为空');
    if (!q.explain || q.explain.length < 8) errs.push('缺少解析');
    if (Array.isArray(q.options) && new Set(q.options).size !== q.options.length) errs.push('选项有重复');
  } else if (type === 'code') {
    if (!q.statement || q.statement.length < 10) errs.push('缺少题目描述');
    if (!q.solution || q.solution.length < 20) errs.push('缺少参考答案');
    if (!q.title) errs.push('缺少标题');
  } else {
    errs.push(`未知类型：${type}`);
  }

  if (errs.length) {
    problems.push({ id, errs });
  } else {
    seen.add(q.id);
    accepted.push({ ...q, type });
  }
}

console.log('');
console.log(`  批次文件：${path.basename(batchPath)}`);
console.log(`  待合并：${incoming.length} 道`);
console.log(`  通过：${accepted.length} 道`);
console.log(`  问题：${problems.length} 道`);
if (problems.length) {
  console.log('');
  problems.forEach((p) => console.log(`   ✗ ${p.id}: ${p.errs.join('；')}`));
}
if (dry) {
  console.log('\n  （--dry：未写入）');
  process.exit(problems.length ? 1 : 0);
}

if (!accepted.length) {
  console.log('\n  没有可写入的题目。');
  process.exit(1);
}

const merged = {
  ...bank,
  questions: [...(bank.questions || []), ...accepted],
};
fs.writeFileSync(bankPath, JSON.stringify(merged, null, 2), 'utf8');

const mcq = merged.questions.filter((q) => (q.type || 'mcq') === 'mcq').length;
const code = merged.questions.length - mcq;
console.log('');
console.log(`  已写入：${bankPath}`);
console.log(`  题库现在：共 ${merged.questions.length} 道（选择题 ${mcq} / 编程题 ${code}）`);
console.log('');
process.exit(problems.length ? 1 : 0);
