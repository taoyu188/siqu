"""
教材 PDF → 干净章节文本
==================================================================
本脚本只做"提取 + 清洗"，不生成题目（出题需要更强的模型，单独一步）。

用法：
  py tools\\pdf-extract.py --pdf "课本.pdf" --toc
      只打印目录（章节标题 + 起止页），用来确认结构

  py tools\\pdf-extract.py --pdf "课本.pdf" --out siqu\\textbook
      按章节切分并输出 txt + manifest.json

  py tools\\pdf-extract.py --pdf "课本.pdf" --out ... --from-page 30 --to-page 120
      只处理指定页范围（书没有内嵌目录时的兜底）

清洗策略：
  1. 识别并删除页眉/页脚（在多页重复出现的行）
  2. 删除孤立页码行
  3. 合并被 PDF 硬折行切断的段落（中文行尾无标点则与下一行拼接）
  4. 压缩连续空行
"""
import argparse
import json
import os
import re
import sys
from collections import Counter

try:
    import fitz  # PyMuPDF
except ImportError:
    print("缺少 PyMuPDF，请先执行：py -m pip install PyMuPDF", file=sys.stderr)
    sys.exit(1)


# ---------------- 基础提取 ----------------
def load_doc(path):
    doc = fitz.open(path)
    return doc


def page_text(doc, i):
    return doc[i].get_text("text")


def get_toc(doc):
    """返回 [(level, title, page1based), ...]"""
    return doc.get_toc(simple=True) or []


# ---------------- 清洗 ----------------
PAGE_NO_RE = re.compile(r"^\s*[-—–\s]*\d{1,4}[-—–\s]*$")
DOTS_RE = re.compile(r"[\.·…]{4,}")


def find_repeated_lines(pages, threshold=0.35):
    """在多页重复出现的短行 → 页眉/页脚"""
    counter = Counter()
    total = len(pages)
    for lines in pages:
        seen = set()
        for ln in lines:
            s = ln.strip()
            if not s or len(s) > 60:
                continue
            if s in seen:
                continue
            seen.add(s)
            counter[s] += 1
    min_hits = max(3, int(total * threshold))
    return {s for s, n in counter.items() if n >= min_hits}


def clean_lines(lines, repeated):
    out = []
    for ln in lines:
        s = ln.strip()
        if not s:
            out.append("")
            continue
        if s in repeated:          # 页眉页脚
            continue
        if PAGE_NO_RE.match(s):    # 孤零零的页码
            continue
        if DOTS_RE.search(s) and len(s) < 40:  # 目录里的点线（正文里不会这样）
            continue
        out.append(s)
    return out


def merge_wrapped(lines):
    """中文段落被硬折行：行尾不是句末标点，就和下一行接起来"""
    ends = "。！？；：”’）】》.!?;:)\"'"
    out = []
    buf = ""
    for ln in lines:
        if not ln:
            if buf:
                out.append(buf)
                buf = ""
            out.append("")
            continue
        if not buf:
            buf = ln
            continue
        if buf and buf[-1] in ends:
            out.append(buf)
            buf = ln
        else:
            # 短行（标题）不与下一行合并
            if len(buf) <= 12 and not buf.endswith(("，", ",", "、", "（", "(")):
                out.append(buf)
                buf = ln
            else:
                buf += ln
    if buf:
        out.append(buf)
    return out


def tidy(text):
    text = re.sub(r"[ \t]+\n", "\n", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def clean_pages(raw_pages):
    repeated = find_repeated_lines(raw_pages)
    cleaned = []
    for lines in raw_pages:
        cl = clean_lines(lines, repeated)
        cleaned.append(merge_wrapped(cl))
    return cleaned, repeated


# ---------------- 章节切分 ----------------
def split_chapters(doc, toc):
    """有内嵌目录就按目录切；否则整本作为一章"""
    if not toc:
        return [(1, "全文", 1, doc.page_count)]

    # 只取 level 1（章），level 2 作为子节标题保留在正文里
    chapters = []
    entries = [t for t in toc if t[0] == 1]
    for idx, (lvl, title, page) in enumerate(entries):
        start = max(1, page)
        end = (entries[idx + 1][2] - 1) if idx + 1 < len(entries) else doc.page_count
        if end < start:
            end = start
        chapters.append((lvl, title, start, end))
    return chapters


def safe_name(title, idx):
    s = re.sub(r"[\\/:*?\"<>|\r\n\t]", "_", title).strip()
    s = re.sub(r"\s+", "_", s)
    if not s:
        s = "chapter"
    return f"{idx:02d}_{s[:40]}"


# ---------------- 主流程 ----------------
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pdf", required=True)
    ap.add_argument("--out", default="")
    ap.add_argument("--toc", action="store_true", help="只打印目录")
    ap.add_argument("--from-page", type=int, default=1)
    ap.add_argument("--to-page", type=int, default=0)
    ap.add_argument("--min-chars", type=int, default=200, help="章节少于这么多字就跳过")
    args = ap.parse_args()

    if not os.path.exists(args.pdf):
        print(f"找不到文件：{args.pdf}", file=sys.stderr)
        sys.exit(1)

    doc = load_doc(args.pdf)
    toc = get_toc(doc)
    print(f"页数：{doc.page_count}")
    print(f"内嵌目录：{'有 ' + str(len(toc)) + ' 条' if toc else '无（将按页范围处理）'}")

    if args.toc:
        if not toc:
            print("\n没有内嵌目录。可以先用 --from-page/--to-page 抽取，或手动指定章节页码。")
            # 打印前几页的文本密度，帮他判断是不是文字版
            print("\n前 3 页各取前 120 字：")
            for i in range(min(3, doc.page_count)):
                t = page_text(doc, i).strip().replace("\n", " ")
                print(f"  p{i+1}: {t[:120]}")
        else:
            print("\n章节列表：")
            for lvl, title, page in toc:
                indent = "  " * (lvl - 1)
                print(f"  {indent}[L{lvl}] p{page:<4} {title}")
        doc.close()
        return

    # 抽取范围
    if args.to_page and args.to_page > 0:
        chapters = [(1, f"第{args.from_page}-{args.to_page}页", args.from_page, args.to_page)]
    else:
        chapters = split_chapters(doc, toc)

    # 先把所有页文本读出来（用于识别页眉页脚）
    all_raw = []
    for i in range(doc.page_count):
        all_raw.append(page_text(doc, i).splitlines())
    cleaned, repeated = clean_pages(all_raw)
    doc.close()

    print(f"\n识别到重复行（页眉/页脚）{len(repeated)} 条：")
    for s in list(repeated)[:8]:
        print(f"   · {s[:60]}")

    os.makedirs(args.out, exist_ok=True)
    manifest = {"pdf": os.path.basename(args.pdf), "pages": len(all_raw), "chapters": []}

    for idx, (lvl, title, start, end) in enumerate(chapters, 1):
        body = []
        for p in range(start - 1, min(end, len(cleaned))):
            body.extend(cleaned[p])
            body.append("")
        text = tidy("\n".join(body))
        if len(text) < args.min_chars:
            print(f"  跳过（内容太少 {len(text)} 字）：{title}")
            continue

        name = safe_name(title, idx)
        path = os.path.join(args.out, name + ".txt")
        with open(path, "w", encoding="utf-8") as f:
            f.write(f"# {title}\n\n")
            f.write(text)
        manifest["chapters"].append({
            "index": idx,
            "title": title,
            "pages": [start, end],
            "chars": len(text),
            "file": name + ".txt",
        })
        print(f"  ✓ {name}.txt  p{start}-{end}  {len(text)} 字")

    with open(os.path.join(args.out, "manifest.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)
    print(f"\n完成：{len(manifest['chapters'])} 章，输出到 {args.out}")


if __name__ == "__main__":
    main()
