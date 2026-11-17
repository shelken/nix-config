"""功能文件形式检查（docs/adr/0012-feature-domains-and-file-form.md）

ast-grep 只看单个文件的语法树，这三条要同时看路径与目录内容，所以单独成脚本：
- 只装一个 default.nix 的目录：没有资源，应改成 <名>.nix
- 只把功能挂进角色、自己不发布模块的文件：转发壳，挂接写回功能本身
- 发布的模块里没有与文件名同名的：模块名即文件名；领域聚合模块（与一级目录同名，如 ai）例外
"""

import re
import subprocess
import sys
from pathlib import Path

FEATURES = "modules/features"
# 只算定义：`config.flake.modules.<类>.<名>` 是引用别人的模块
MODULE = re.compile(r'(?<![\w.])flake\.modules\.(?:darwin|nixos|homeManager)\."?([A-Za-z0-9_-]+)"?')

roles = {p.stem for p in Path("modules/profiles").glob("*.nix")}
files = subprocess.run(
    ["git", "ls-files", FEATURES], capture_output=True, text=True, check=True
).stdout.split()

errors = []

dirs = {}
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
    text = p.read_text()
    if not MODULE.search(text):
        continue
    names = set(MODULE.findall(text)) - roles
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
