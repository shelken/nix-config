import argparse
import json
import os
import re
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BASELINE = Path(__file__).resolve().with_name("no-comments-baseline.json")
AST_GREP = os.environ.get("AST_GREP", "ast-grep")
LANGS = ("nix", "python", "bash", "typescript", "lua")
IGNORES = '["lint/rule-tests/**", "modules/features/ai/browser-automation/agent-browser/templates/**"]'
RULES = "\n---\n".join(
    f"id: {lang}\nlanguage: {lang}\nignores: {IGNORES}\nrule: {{ kind: comment }}"
    for lang in LANGS
)


def is_external(raw: str) -> bool:
    s = raw.strip()
    if s.startswith("/*"):
        s = s[2:-2] if s.endswith("*/") else s[2:]
    elif s.startswith("--"):
        m = re.match(r"^--\[(=*)\[(.*)\]\1\]$", s, re.DOTALL)
        s = m.group(2) if m else s[2:]
    cleaned = [re.sub(r"^[\s#/*-]+", "", ln).strip() for ln in s.splitlines()]
    non_empty = [ln for ln in cleaned if ln]
    if not non_empty or not non_empty[0].startswith("EXTERNAL:"):
        return False
    return bool(non_empty[0][9:].strip() or len(non_empty) > 1)


def scan() -> dict[str, list[tuple[int, int, str]]]:
    tracked = set(
        subprocess.run(
            ["git", "ls-files", "-z"], cwd=ROOT, capture_output=True, text=True, check=True
        ).stdout.split("\0")
    )
    raw = subprocess.run(
        [AST_GREP, "scan", "--json=compact", "--inline-rules", RULES],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    grouped: dict[str, list[dict]] = defaultdict(list)
    for m in json.loads(raw or "[]"):
        rel = Path(m["file"]).as_posix().removeprefix("./")
        if rel in tracked:
            grouped[rel].append(m)

    out: dict[str, list[tuple[int, int, str]]] = {}
    for rel, matches in sorted(grouped.items()):
        ordered = sorted(
            matches,
            key=lambda m: (m["range"]["start"]["line"], m["range"]["start"]["column"]),
        )
        items: list[tuple[int, int, str]] = []
        for m in ordered:
            start = m["range"]["start"]["line"] + 1
            end = m["range"]["end"]["line"] + 1
            col = m["range"]["start"]["column"]
            text = m["text"]
            s = text.strip()
            if start == 1 and col == 0 and (s.startswith("#!") or s.startswith("#compdef ")):
                continue
            if s.startswith("# renovate:") or is_external(text):
                continue
            items.append((start, end, text))
        if items:
            out[rel] = items
    return out


def count_lines(items: list[tuple[int, int, str]]) -> int:
    return sum(end - start + 1 for start, end, _ in items)


def matches_prefix(rel: str, prefixes: list[str]) -> bool:
    return any(rel == pf.rstrip("/") or rel.startswith(pf.rstrip("/") + "/") for pf in prefixes)


def write_baseline(counts: dict[str, int], old_total: int) -> None:
    nonzero = {rel: val for rel, val in sorted(counts.items()) if val > 0}
    BASELINE.write_text(json.dumps(nonzero, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Updated {BASELINE.name}: {old_total} -> {sum(nonzero.values())} lines "
          f"({len(nonzero)} files)")


def main() -> int:
    p = argparse.ArgumentParser(description="ast-grep comment ratchet")
    p.add_argument("prefix", nargs="*", help="Path prefix filter (only for --dump)")
    p.add_argument("--check", action="store_true", help="Read-only check, fails on any drift")
    p.add_argument("--tighten", "--update-baseline", dest="tighten", action="store_true",
                   help="Fail on increase, auto-tighten baseline on decrease")
    p.add_argument("--dump", action="store_true", help="Print non-exempt comments")
    args = p.parse_args()

    if args.prefix and not args.dump:
        print("ERROR: 路径参数仅支持与 --dump 搭配使用", file=sys.stderr)
        return 1

    scanned = scan()
    if args.dump:
        total = files = 0
        for rel, items in scanned.items():
            if args.prefix and not matches_prefix(rel, args.prefix):
                continue
            files += 1
            total += count_lines(items)
            for s, e, t in items:
                span = f"{s}-{e}" if e != s else str(s)
                print(f"{rel}:{span}  {t.splitlines()[0].strip()}")
        print(f"summary: {total} lines across {files} files")
        return 0

    had_base = BASELINE.exists() and BASELINE.stat().st_size > 0
    old: dict[str, int] = json.loads(BASELINE.read_text(encoding="utf-8")) if had_base else {}
    cur = {rel: count_lines(items) for rel, items in scanned.items()}

    if not had_base:
        if args.tighten:
            write_baseline(cur, 0)
            return 0
        print(f"ERROR: 缺少基线 {BASELINE}", file=sys.stderr)
        return 1

    errors: list[str] = []
    stale: list[str] = []
    for rel in sorted({*old, *cur}):
        allowed = old.get(rel, 0)
        actual = cur.get(rel, 0)
        if actual > allowed:
            lines = [f"  L{s}: {t.splitlines()[0].strip()}" for s, _, t in scanned[rel]]
            errors.append(f"{rel}: {actual} 行注释超过基线 {allowed}\n" + "\n".join(lines))
        elif actual < allowed:
            stale.append(f"{rel}: {allowed} -> {actual}")

    if errors:
        for err in errors:
            print(f"ERROR: {err}", file=sys.stderr)
        return 1

    if stale:
        if args.tighten:
            write_baseline(cur, sum(old.values()))
            return 0
        print(
            f"ERROR: {len(stale)} 个文件注释已减少但基线未收紧，"
            "运行 python3 lint/no-comments.py --tighten：\n  " + "\n  ".join(stale[:10]),
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
