import json
import os
import re
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
AST_GREP = os.environ.get("AST_GREP", "ast-grep")
FEATURES = "modules/features"
ATTR = re.compile(r'^flake\.modules\.(?:darwin|nixos|homeManager)\."?([A-Za-z0-9_-]+)"?')
RULE = (
    "id: flake-module\n"
    "language: nix\n"
    "rule:\n"
    "  kind: attrpath\n"
    "  regex: ^flake\\.modules\\.(darwin|nixos|homeManager)\\.\n"
)

roles = {p.stem for p in (ROOT / "modules/profiles").glob("*.nix")}
files = [
    p
    for p in subprocess.run(
        ["git", "ls-files", "-z", FEATURES],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=True,
    ).stdout.split("\0")
    if p
]

raw = subprocess.run(
    [AST_GREP, "scan", "--json=compact", "--inline-rules", RULE, FEATURES],
    cwd=ROOT,
    capture_output=True,
    text=True,
    check=True,
).stdout
published: dict[str, set[str]] = defaultdict(set)
for m in json.loads(raw or "[]"):
    hit = ATTR.match(m["text"])
    if hit:
        published[Path(m["file"]).as_posix().removeprefix("./")].add(hit.group(1))

errors = []
dirs: dict[Path, list[str]] = {}
for f in files:
    for parent in Path(f).parents:
        if parent == Path(FEATURES):
            break
        dirs.setdefault(parent, []).append(f)
for d, members in sorted(dirs.items()):
    if members == [str(d / "default.nix")]:
        errors.append(f"{d}/default.nix：目录里没有资源，改成 {d}.nix")

for f in files:
    p = Path(f)
    if p.suffix != ".nix" or any(part.startswith("_") for part in p.parts):
        continue
    all_names = published.get(f, set())
    if not all_names:
        continue
    names = all_names - roles
    if not names:
        errors.append(f"{f}：只把功能挂进角色、自己不发布模块，挂接写回功能本身")
        continue
    name = p.parent.name if p.name == "default.nix" else p.stem
    domain = p.relative_to(FEATURES).parts[0]
    if name not in names and domain not in names:
        errors.append(f"{f}：发布的模块 {', '.join(sorted(names))} 里没有与文件名同名的 {name}")

for e in errors:
    print(e)
sys.exit(1 if errors else 0)
