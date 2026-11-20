import re
import subprocess
import sys
from pathlib import Path

FEATURES = "modules/features"
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
