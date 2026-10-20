# -*- coding: utf-8 -*-
"""
OCR 结果 → 干净章节文本
==================================================================
输入：ocr-book.ps1 产出的 pages/pNNN.txt（每页 OCR 原始文本）
输出：chapters/*.txt + manifest.json

清洗做什么：
  1. 去掉汉字之间的空格（OCR 常见：把每个字当成独立词）
  2. 跨页重复行（页眉/页脚/书名/页码）自动识别并删除
  3. 代码行归一化：全角标点转 ASCII（`（` → `(`、`；` → `;`）
  4. 合并被硬折行截断的中文段落
  5. 按「第X章」切分章节

用法：
  py tools\\build-book.py --dir D:\\Projects\\siqu\\textbook
  py tools\\build-book.py --dir ... --report       只打印统计，不写文件
"""
import argparse
import json
import os
import re
import sys
from collections import Counter

CJK = r'\u4e00-\u9fa5\u3000-\u303f\uff00-\uffef'

def collapse_cjk_spaces(text):
    """汉字/中文标点之间的单个空格去掉：'第 4 章 循 环' → '第4章循环'"""
    prev = None
    while prev != text:
        prev = text
        text = re.sub(r'(?<=[' + CJK + r'])[ \t]+(?=[' + CJK + r'])', '', text)
    # 汉字与阿拉伯数字之间也常有空格，但保留一个（如"第 4 章"→"第4章"）
    text = re.sub(r'(?<=[\u4e00-\u9fa5])[ \t]+(?=\d)', '', text)
    text = re.sub(r'(?<=\d)[ \t]+(?=[\u4e00-\u9fa5])', '', text)
    return text


FULL2ASCII = {'（': '(', '）': ')', '，': ',', '；': ';', '：': ':', '＝': '=',
              '＋': '+', '－': '-', '＊': '*', '／': '/', '＜': '<', '＞': '>',
              '＂': '"', '＇': "'", '％': '%', '＆': '&', '｜': '|', '！': '!',
              '［': '[', '］': ']', '｛': '{', '｝': '}', '＃': '#', '．': '.'}

CODE_HINTS = re.compile(
    r'(^#include|^#define|^int\s|^void\s|^float\s|^double\s|^char\s|^for\s*\(|^while\s*\(|'
    r'^if\s*\(|^else|^return|printf|scanf|main\s*\(|;|\{|\})'
)

def normalize_code_line(line):
    """代码行：全角标点转 ASCII，并去掉多余空格"""
    if not CODE_HINTS.search(line):
        return line
    out = ''.join(FULL2ASCII.get(ch, ch) for ch in line)
    out = re.sub(r'\s+([,;)\]])', r'\1', out)
    out = re.sub(r'([(\[])\s+', r'\1', out)
    return out.strip()


# OCR 高频错字（保守：只放确定不会误伤的）
OCR_FIX = {
    '循坏': '循环',
    '设讠': '设计',
    'prmtf': 'printf',
    '输人': '输入',
    '夕卜部': '外部',
    '练习题': '练习题',
    '字符申': '字符串',
    '指什': '指针',
    '函教': '函数',
}

def fix_ocr(line):
    for bad, good in OCR_FIX.items():
        if bad in line:
            line = line.replace(bad, good)
    return line

PAGE_NO = re.compile(r'^[\s\-—–·]*\d{1,4}[\s\-—–·]*$')
CHAPTER = re.compile(r'^第\s*([0-9一二三四五六七八九十百]+)\s*章\s*(.*)$')


def load_pages(pages_dir):
    files = sorted(f for f in os.listdir(pages_dir) if re.match(r'p\d+\.txt$', f))
    pages = []
    for f in files:
        pno = int(re.search(r'\d+', f).group())
        with open(os.path.join(pages_dir, f), encoding='utf-8', errors='replace') as fh:
            lines = [collapse_cjk_spaces(ln) for ln in fh.read().splitlines()]
        pages.append((pno, lines))
    return pages


def norm_key(s):
    """归一化用于比对：去掉标点空格，取前 8 个字（OCR 常有细微差异）"""
    t = re.sub(r'[^0-9A-Za-z\u4e00-\u9fa5]', '', s)
    return t[:5]


def repeated_lines(pages, threshold=0.30, max_len=40):
    """在多页重复出现的短行 → 页眉/页脚（模糊匹配，容忍 OCR 变体）"""
    c = Counter()
    for _, lines in pages:
        seen = set()
        for ln in lines:
            s = ln.strip()
            if not s or len(s) > max_len:
                continue
            k = norm_key(s)
            if len(k) < 3 or k in seen:
                continue
            seen.add(k)
            c[k] += 1
    need = max(3, int(len(pages) * threshold))
    return {k for k, n in c.items() if n >= need}


def clean_page(lines, repeated):
    out = []
    for ln in lines:
        s = ln.strip()
        if not s:
            out.append('')
            continue
        if PAGE_NO.match(s):
            continue
        if repeated and norm_key(s) in repeated:
            continue
        # 页眉样式的行（"第3章分支程序设计"）——真正的章标题已单独记录
        if len(s) <= 16 and re.match(r'^第\s*\d+\s*章', s):
            continue
        s = fix_ocr(s)
        s = normalize_code_line(s)
        out.append(s)
    return out


ENDS = '。！？；：”’）】》.!?;:)"'
def merge_wrapped(lines):
    out, buf = [], ''
    for ln in lines:
        if not ln:
            if buf:
                out.append(buf); buf = ''
            out.append('')
            continue
        if not buf:
            buf = ln
            continue
        # 上一行结尾是句末标点，或本身很短（标题），就换段
        if buf[-1] in ENDS or len(buf) <= 14:
            out.append(buf); buf = ln
        else:
            buf += ln
    if buf:
        out.append(buf)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--dir', required=True, help='ocr-book.ps1 的输出目录')
    ap.add_argument('--report', action='store_true')
    args = ap.parse_args()

    pages_dir = os.path.join(args.dir, 'pages')
    if not os.path.isdir(pages_dir):
        print(f'找不到 {pages_dir}', file=sys.stderr)
        sys.exit(1)

    pages = load_pages(pages_dir)
    print(f'读入 {len(pages)} 页')
    if not pages:
        sys.exit(1)

    repeated = repeated_lines(pages)
    print(f'识别到重复行（页眉/页脚）{len(repeated)} 条：')
    for s in list(repeated)[:10]:
        print(f'   · {s}')

    # 清洗 + 合并
    cleaned = []
    for pno, lines in pages:
        cl = clean_page(lines, repeated)
        cleaned.append((pno, merge_wrapped(cl)))

    # 找章节起点：页眉每页都有「第N章」，所以只在【原始未清洗】的页里
    # 取每章第一次出现的位置 —— 那就是该章真正的起始页
    # 先标记目录页：一页里出现 >=3 个不同的「第N章」→ 是目录，跳过
    toc_pages = set()
    for idx, (pno, raw_lines) in enumerate(pages):
        nums = set()
        for ln in raw_lines:
            m = CHAPTER.match(ln.strip())
            if m and len(ln.strip()) <= 30:
                nums.add(m.group(1))
        if len(nums) >= 3:
            toc_pages.add(idx)

    # 先找"正文起点"：第1章第一次出现的页。它之前的「第N章」都是目录/前言
    # 正文页的页眉在第一行；目录页第一行是「目录」，所以用第一行判定
    body_start = 0
    for idx, (pno, raw_lines) in enumerate(pages):
        first = next((l.strip() for l in raw_lines if l.strip()), '')
        if CHAPTER.match(first):
            body_start = idx
            break
    print(f'正文起点：第 {body_start + 1} 页')

    # 每章取「正文起点之后、非目录页」的首次出现
    first_seen = {}
    for idx, (pno, raw_lines) in enumerate(pages):
        if idx < body_start or idx in toc_pages:
            continue
        for ln in raw_lines:
            m = CHAPTER.match(ln.strip())
            if not m or len(ln.strip()) > 30:
                continue
            num = m.group(1)
            if num in first_seen:
                continue
            first_seen[num] = {'no': num, 'title': ln.strip(), 'start_idx': idx, 'page': pno}
    # 按章号排序，要求页码严格递增；不满足的（目录页误检）丢弃
    ordered = sorted(first_seen.values(), key=lambda c: int(c['no']) if c['no'].isdigit() else 99)
    chapters = []
    last_page = 0
    for c in ordered:
        if c['page'] <= last_page:
            print(f"   丢弃可疑章节：第{c['no']}章 p{c['page']}（页码未递增）")
            continue
        chapters.append(c)
        last_page = c['page']
    chapters.sort(key=lambda c: c['start_idx'])
    if toc_pages:
        print(f'跳过目录页 {len(toc_pages)} 页')

    if not chapters:
        print('\n没找到「第X章」标题，整本作为一章输出')
        chapters = [{'no': '0', 'title': '全文', 'start_idx': 0, 'page': cleaned[0][0]}]

    print(f'\n识别到 {len(chapters)} 章：')
    for c in chapters:
        print(f"   第{c['no']}章  p{c['page']:<4} {c['title'][:40]}")

    if args.report:
        return

    out_dir = os.path.join(args.dir, 'chapters')
    os.makedirs(out_dir, exist_ok=True)
    manifest = {'pages': len(pages), 'chapters': []}

    for i, c in enumerate(chapters):
        start = c['start_idx']
        end = chapters[i + 1]['start_idx'] if i + 1 < len(chapters) else len(cleaned)
        body = []
        for _, lines in cleaned[start:end]:
            body.extend(lines)
            body.append('')
        text = re.sub(r'\n{3,}', '\n\n', '\n'.join(body)).strip()
        if len(text) < 300:
            continue
        name = f"{i+1:02d}_第{c['no']}章"
        path = os.path.join(out_dir, name + '.txt')
        with open(path, 'w', encoding='utf-8') as f:
            f.write(f"# {c['title']}\n\n{text}")
        manifest['chapters'].append({
            'index': i + 1, 'no': c['no'], 'title': c['title'],
            'pages': [c['page'], cleaned[end - 1][0] if end - 1 < len(cleaned) else cleaned[-1][0]],
            'chars': len(text), 'file': name + '.txt',
        })
        print(f"   ✓ {name}.txt  {len(text)} 字")

    with open(os.path.join(args.dir, 'manifest.json'), 'w', encoding='utf-8') as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)
    print(f"\n完成：{len(manifest['chapters'])} 章 → {out_dir}")


if __name__ == '__main__':
    main()
