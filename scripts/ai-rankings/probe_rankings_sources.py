#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""大模型天梯三源的只读探测：某个模型在不在源数据里，以及它为什么没进 data.json。

回答的只有一个问题——**没上榜是源头没有，还是被我们自己的规则挡掉的**。两者的处理
方式完全相反：源头没有就只能等，被规则挡掉才是要改的东西。凭印象猜是哪一种，等于
把「等一天」和「有个 bug」当成同一件事。

约定：

- 抓取与合并全部复用 `build_rankings.py` 的函数，不另起一套口径（否则探测结论
  与日更管道说的不是同一件事）；
- 只打印报告，不写 `apps/` 下任何数据，也不提交仓库；
- 报告给出关键词在三源中的原始条目、归一后的合并键，以及它在合并排序里的名次与
  被哪条规则拦下。

用法：

    python scripts/ai-rankings/probe_rankings_sources.py --find gpt-6,astra
    python scripts/ai-rankings/probe_rankings_sources.py --self-test   # 离线自检
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_rankings as br  # noqa: E402  （同目录脚本，插完路径才能导入）

# 源名 → (源内分值字段, 该源写进模型的字段)
SRC_VALUE = {"Arena": ("elo", "arena"), "LiveBench": ("avg", "livebench"), "AA": ("aa", "aa")}


def hits(src, needles):
    """在 {合并键: 记录} 里找关键词；合并键与原始名都参与匹配。"""
    if not src or not needles:
        return []
    out = []
    for k, v in src.items():
        hay = (k + " " + str(v.get("raw", ""))).lower()
        if any(n in hay for n in needles):
            out.append((k, v))
    return sorted(out)


def axis_count(m):
    return sum(1 for k in br.AXES if isinstance(m.get(k), (int, float)))


def report(arena, lb, aa, prev, needles, top):
    """把三源与合并结果打成人可读的报告。返回结论行的列表，便于自检断言。"""
    srcs = [("Arena", arena), ("LiveBench", lb), ("AA", aa)]

    print("\n=== 一、三源可达性 ===")
    for label, src in srcs:
        print(f"  {label:<10}{('取到 %d 条' % len(src)) if src else '本次无数据（该轴将沿用上次 data.json 的值）'}")

    print("\n=== 二、各源分值最高的 12 条（源里的原始名）===")
    for label, src in srcs:
        if not src:
            continue
        vkey = SRC_VALUE[label][0]
        rows = sorted(src.items(), key=lambda kv: kv[1][vkey], reverse=True)[:12]
        print(f"  --- {label} ---")
        for k, v in rows:
            print(f"    {v[vkey]:>7}  {v.get('raw')}   [合并键 {k}]")

    print("\n=== 三、关键词在三源中的命中 ===")
    if not needles:
        print("  （未给 --find，跳过）")
    for n in needles:
        print(f"  --- 「{n}」 ---")
        any_hit = False
        for label, src in srcs:
            for k, v in hits(src, [n]):
                any_hit = True
                print(f"    {label}: {v.get('raw')}  分值 {v[SRC_VALUE[label][0]]}  [合并键 {k}]")
        if not any_hit:
            print("    三源都没有这个名字")

    prev_models = {m["id"]: m for m in (prev or {}).get("models", [])}
    ranked = br.score_models(br.merge_sources(arena, lb, aa, prev_models))

    print(f"\n=== 四、合并排序（共 {len(ranked)} 个；data.json 只收前 {br.TOP_N} 名）===")
    for i, m in enumerate(ranked[:top], 1):
        mark = "  " if i <= br.TOP_N else "✂ "
        print(f"  {mark}{i:>3}. {m['name']:<26} {axis_count(m)} 榜  综合 {m['_combo']:.4f}  "
              f"arena={m['arena']} lb={m['livebench']} aa={m['aa']}")
    if len(ranked) > top:
        print(f"  …… 其余 {len(ranked) - top} 个略")

    multi = [m for m in ranked if axis_count(m) >= 2]
    single = [m for m in ranked if axis_count(m) == 1]
    first_single = next((i for i, m in enumerate(ranked, 1) if axis_count(m) == 1), None)
    print("\n=== 五、单榜模型的处境 ===")
    print(f"  ≥2 榜 {len(multi)} 个，单榜 {len(single)} 个；单榜模型一律排在多榜模型之后，"
          f"第一个单榜模型位于第 {first_single} 名。")
    print(f"  因此单榜模型能进 data.json 的名额只有 {max(0, br.TOP_N - len(multi))} 个；"
          "且前端「综合」页会把单榜模型整个滤掉（综合分为空），只在对应的单榜页里出现。")

    print("\n=== 六、结论 ===")
    lines = []
    for n in needles:
        in_src = [label for label, src in srcs if hits(src, [n])]
        rows = [(i, m) for i, m in enumerate(ranked, 1)
                if n in (m["id"] + " " + m["name"]).lower()]
        if not in_src:
            lines.append(f"「{n}」：三源都没有 —— 上不了榜是源头还没收录，不是本站规则挡的，只能等。")
        elif not rows:
            lines.append(f"「{n}」：{'/'.join(in_src)} 里有，但合并阶段被丢弃"
                         "（多半是认不出厂商：merge_sources 会跳过 org 为空的长尾模型）。")
        else:
            for i, m in rows:
                n_ax = axis_count(m)
                if i <= br.TOP_N:
                    verdict = f"进 data.json（第 {i} 名）"
                    if n_ax < 2:
                        verdict += "，但只有 1 榜有数据，前端「综合」页看不到它"
                else:
                    verdict = f"排第 {i} 名，被前 {br.TOP_N} 名截断挡在 data.json 之外"
                lines.append(f"「{n}」：命中 {'/'.join(in_src)}；{n_ax} 榜有数据 → {verdict}")
    for ln in lines or ["（未给 --find，无结论）"]:
        print("  " + ln)
    return lines


def self_test():
    """离线自检：用构造的三源跑一遍报告，确认结论分支判得对。"""
    arena = {
        "alpha-1": {"raw": "Alpha 1", "elo": 1500, "org": "OpenAI", "open": None, "ctx": None, "price": None},
        "beta-2": {"raw": "Beta 2", "elo": 1400, "org": "Google", "open": None, "ctx": None, "price": None},
        "solo-9": {"raw": "Solo 9", "elo": 1300, "org": "Anthropic", "open": None, "ctx": None, "price": None},
        "nobody-1": {"raw": "Nobody 1", "elo": 1200, "org": None, "open": None, "ctx": None, "price": None},
    }
    lb = {"alpha-1": {"raw": "Alpha 1", "avg": 80.0, "org": "OpenAI", "open": False},
          "beta-2": {"raw": "Beta 2", "avg": 70.0, "org": "Google", "open": False}}
    lines = report(arena, lb, None, None, ["alpha", "solo", "nobody", "ghost"], top=10)
    joined = "\n".join(lines)
    checks = [
        ("2 榜有数据" in joined and "alpha" in joined, "两榜模型应判为 2 榜有数据"),
        ("前端「综合」页看不到它" in joined, "单榜模型应提示前端综合页看不到"),
        ("合并阶段被丢弃" in joined, "认不出厂商的模型应判为合并阶段被丢弃"),
        ("三源都没有" in joined, "源里没有的名字应判为源头没收录"),
    ]
    bad = [msg for ok, msg in checks if not ok]
    print("\n=== 自检 ===")
    for msg in bad:
        print("  ✗ " + msg)
    if bad:
        return 1
    print(f"  ✓ {len(checks)} 项全过")
    return 0


def main():
    ap = argparse.ArgumentParser(description="大模型天梯三源只读探测")
    ap.add_argument("--find", default="", help="要查的模型关键词，逗号分隔，例如 gpt-6,astra")
    ap.add_argument("--top", type=int, default=50, help="打印合并排序的前 N 名（默认 50）")
    ap.add_argument("--self-test", action="store_true", help="离线自检，不联网")
    args = ap.parse_args()

    if args.self_test:
        return self_test()

    needles = [s.strip().lower() for s in args.find.split(",") if s.strip()]
    print("抓取 LMArena…"); arena = br.fetch_arena()
    print("抓取 LiveBench…"); lb = br.fetch_livebench()
    print("抓取 Artificial Analysis…"); aa = br.fetch_aa()
    if not arena and not lb and not aa:
        print("\n三源全部取不到，本次探测没有结论（不代表榜单里没有这个模型）。")
        return 1
    report(arena, lb, aa, br.load_prev(), needles, args.top)
    return 0


if __name__ == "__main__":
    sys.exit(main())
