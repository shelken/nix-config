#!/usr/bin/env python3
# 在 SKILL.md frontmatter 块内确保指定键存在；已存在则跳过，不覆盖。
import json
import re
import sys

path = sys.argv[1]
overrides = json.loads(sys.argv[2])

text = open(path, encoding="utf-8").read()
m = re.match(r"^---\n(.*?\n)---\n?(.*)$", text, re.DOTALL)
if not m:
    sys.exit(0)  # 无 frontmatter，不动

fm, body = m.group(1), m.group(2)
for k, v in overrides.items():
    if re.search(rf"^{re.escape(k)}:", fm, re.MULTILINE):
        continue
    fm += f"{k}: {json.dumps(v)}\n"

open(path, "w", encoding="utf-8").write(f"---\n{fm}---\n{body}")
