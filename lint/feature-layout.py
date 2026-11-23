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
PLATFORM_FRAGMENTS = {"_hm.nix", "_home.nix", "_darwin.nix", "_nixos.nix"}
LEGACY_PLATFORM_FRAGMENTS = {
    "modules/features/backup/kopia/_hm.nix",
    "modules/features/desktop/tinycast/_hm.nix",
}
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
for f in sorted(LEGACY_PLATFORM_FRAGMENTS - set(files)):
    errors.append(f"{f}：已不存在，请从 lint/feature-layout.py 的 LEGACY_PLATFORM_FRAGMENTS 白名单中移除")

dirs: dict[Path, list[str]] = {}
for f in files:
    for parent in Path(f).parents:
        if parent == Path(FEATURES):
            break
        dirs.setdefault(parent, []).append(f)
for d, members in sorted(dirs.items()):
    if members == [str(d / "default.nix")]:
        errors.append(f"{d}/default.nix：目录里没有资源，改成 {d}.nix")

entry_names: dict[str, list[str]] = defaultdict(list)

for f in files:
    p = Path(f)
    if p.name in PLATFORM_FRAGMENTS and f not in LEGACY_PLATFORM_FRAGMENTS:
        errors.append(f"{f}：不得新增按平台命名的私有片段，请合入入口文件或按职责命名")
    if p.suffix != ".nix" or any(part.startswith("_") for part in p.parts):
        continue
    rel = p.relative_to(FEATURES)
    if not (
        (len(rel.parts) == 2 and rel.parts[1] != "default.nix")
        or (len(rel.parts) == 3 and rel.parts[2] == "default.nix")
    ):
        errors.append(f"{f}：功能入口必须在 <领域>/<名>.nix 或 <领域>/<名>/default.nix，私有片段请以 _ 开头")
        continue
    name = p.parent.name if p.name == "default.nix" else p.stem
    entry_names[name].append(f)
    all_names = published.get(f, set())
    if not all_names:
        continue
    names = all_names - roles
    if not names:
        errors.append(f"{f}：只把功能挂进角色、自己不发布模块，挂接写回功能本身")
        continue
    domain = rel.parts[0]
    if name not in names and domain not in names:
        errors.append(f"{f}：发布的模块 {', '.join(sorted(names))} 里没有与文件名同名的 {name}")

for name, paths in sorted(entry_names.items()):
    if len(paths) > 1:
        errors.append(f"功能文件名 {name} 重复：{', '.join(sorted(paths))}")

for e in errors:
    print(e)
sys.exit(1 if errors else 0)
