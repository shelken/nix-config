#!/usr/bin/env python3
# 覆盖 SKILL.md frontmatter 中的标量字段；缺失字段追加到末尾。
import json
import re
import sys

path = sys.argv[1]
overrides = json.loads(sys.argv[2])

text = open(path, encoding="utf-8").read()
match = re.match(r"^---\n(.*?\n)---\n?(.*)$", text, re.DOTALL)
if not match:
    sys.exit(0)

frontmatter, body = match.groups()
for key, value in overrides.items():
    replacement = f"{key}: {json.dumps(value)}\n"
    pattern = rf"^{re.escape(key)}:[^\n]*(?:\n|$)"
    frontmatter, count = re.subn(pattern, replacement, frontmatter, count=1, flags=re.MULTILINE)
    if count == 0:
        frontmatter += replacement

open(path, "w", encoding="utf-8").write(f"---\n{frontmatter}---\n{body}")
