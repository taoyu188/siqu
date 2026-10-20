# -*- coding: utf-8 -*-
"""
章节文本 → 知识点清单（给"出题"步骤用的压缩输入）
==================================================================
为什么要压缩：整本 34 万字直接喂给模型很贵。这一步用规则把每章压成
2-3k token 的"考点摘要"，出题时只需要这部分。

提取内容：
  1. 小节标题（1.2 / 第X节 / 例题编号）
  2. 代码片段（#include 开头到 return 结束的块；或连续的含分号行）
  3. 规则型句子（含"注意/不能/必须/等于/从0开始/截断/溢出"等）
  4. 术语密度高的句子（指针/数组/下标/地址/类型/运算/优先级…）

用法：
  py tools\\extract-points.py --dir D:\\Projects\\siqu\\textbook
  py tools\\extract-points.py --dir ... --chapter 4     只做第 4 章
"""
import argparse
import glob
import os
import re

SECTION = re.compile(r'^\s*(\d{1,2}\s*[.．]\s*\d{1,2}|\d{1,2}\s*[.．]\s*\d{1,2}\s*[.．]\s*\d{1,2})\s*(.{2,40})$')
EXAMPLE = re.compile(r'〖\s*例\s*(\d+)\s*[.．\-]\s*(\d+)\s*〗')

RULE_WORDS = ['注意', '必须', '不能', '不允许', '一定要', '否则', '区别', '区别在于',
              '等于', '从0开始', '从 0 开始', '截断', '溢出', '越界', '优先级',
              '自左向右', '自右向左', '类型转换', '隐式', '强制', '返回值', '地址',
              '初始化', '结束符', '关键字', '规则']

TERM_WORDS = ['int', 'float', 'double', 'char', 'scanf', 'printf', '数组', '指针',
              '下标', '字符串', '运算符', '表达式', '循环', '函数', '参数', '递归',
              '结构体', '文件', 'malloc', 'sizeof']


def is_code_line(s):
    return bool(re.search(r'(#include|#define|\bint\b|\bvoid\b|printf|scanf|;\s*$|\{|\})', s))


def collect_code_blocks(lines):
    """把连续 3 行以上的代码聚成块"""
    blocks, cur = [], []
    for ln in lines:
        if is_code_line(ln):
            cur.append(ln)
        else:
            if len(cur) >= 3:
                blocks.append(cur)
            cur = []
    if len(cur) >= 3:
        blocks.append(cur)
    return blocks


def score_sentence(s):
    if len(s) < 12 or len(s) > 160:
        return 0
    sc = 0
    for w in RULE_WORDS:
        if w in s:
            sc += 3
    for w in TERM_WORDS:
        if w in s:
            sc += 1
    if sc and not s.rstrip().endswith(('？', '?', '。')):
        pass
    return sc


def process(chapter_path):
    with open(chapter_path, encoding='utf-8', errors='replace') as f:
        raw = f.read()
    title = raw.splitlines()[0].lstrip('# ').strip() if raw.startswith('#') else os.path.basename(chapter_path)
    lines = [l.strip() for l in raw.splitlines()]

    sections = []
    examples = []
    for ln in lines:
        m = SECTION.match(ln)
        if m and len(ln) <= 46:
            sections.append(ln)
        for em in EXAMPLE.finditer(ln):
            examples.append(f'{em.group(1)}.{em.group(2)}')

    blocks = collect_code_blocks(lines)

    # 规则句：按分数取前 N，去重
    scored = []
    seen = set()
    for ln in lines:
        if is_code_line(ln) or len(ln) < 12:
            continue
        key = ln[:24]
        if key in seen:
            continue
        sc = score_sentence(ln)
        if sc >= 3:
            seen.add(key)
            scored.append((sc, ln))
    scored.sort(key=lambda x: -x[0])
    rules = [s for _, s in scored[:40]]

    out = []
    out.append(f'# {title}\n')
    out.append(f'（来源：{os.path.basename(chapter_path)}）\n')

    if sections:
        out.append('\n## 小节标题\n')
        for s in sections[:30]:
            out.append(f'- {s}')
    if examples:
        uniq = sorted(set(examples), key=lambda x: (int(x.split(".")[0]), int(x.split(".")[1])))
        out.append(f'\n## 例题编号（共 {len(uniq)} 个）\n')
        out.append('- ' + '、'.join(f'例{x}' for x in uniq[:40]))

    if blocks:
        out.append(f'\n## 代码片段（前 {min(len(blocks), 12)} 段 / 共 {len(blocks)} 段）\n')
        for b in blocks[:12]:
            out.append('```')
            out.extend(b[:18])
            out.append('```')

    if rules:
        out.append('\n## 规则型表述（可出题的断言）\n')
        for s in rules:
            out.append(f'- {s}')

    return '\n'.join(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--dir', required=True)
    ap.add_argument('--chapter', type=int, default=0)
    ap.add_argument('--max-chars', type=int, default=9000)
    args = ap.parse_args()

    src = os.path.join(args.dir, 'chapters')
    files = sorted(glob.glob(os.path.join(src, '*.txt')))
    if not files:
        print(f'找不到章节文件：{src}')
        return

    out_dir = os.path.join(args.dir, 'points')
    os.makedirs(out_dir, exist_ok=True)

    for i, path in enumerate(files, 1):
        if args.chapter and i != args.chapter:
            continue
        text = process(path)
        if len(text) > args.max_chars:
            text = text[:args.max_chars] + '\n\n……（已截断）'
        name = os.path.splitext(os.path.basename(path))[0] + '.md'
        with open(os.path.join(out_dir, name), 'w', encoding='utf-8') as f:
            f.write(text)
        print(f'  ✓ {name}  {len(text)} 字')

    print(f'\n输出目录：{out_dir}')


if __name__ == '__main__':
    main()
