#!/usr/bin/env python3
"""把上游 pstack 的 Cursor 方言改写成 omp/pi 可用的形状。

做三件事，全部幂等：
1. 对含 Cursor 专名的 SKILL.md，在首个 H1 之后插入一行指针，指向 harness 适配文档。
2. 把指向 skills/ 之外的相对链接改写成上游 GitHub 地址（安装后这些文件不存在）。
3. 校验被实际用到的每个 Cursor 专名都出现在每份适配文档里，缺失即失败。

用法: adapt.py <pstack-root> <adapter.md>...
"""
import os
import re
import sys

MARKER = "This skill uses Cursor names. In omp or pi, read"
GITHUB = "https://github.com/cursor/plugins"

# 与上游 scripts/generate-pstack-harness-trees.mjs 的 TERMS 保持一致；新增项必须同时进适配文档。
TERMS = [
    ("`Task`", r"`Task`|\bTask (tool|subagent|call)"),
    ("`AskQuestion`", r"AskQuestion"),
    ("todolist", r"\btodo ?list\b"),
    ("generalPurpose", r"generalPurpose"),
    ("poteto-agent", r"poteto-agent"),
    ("comment-sicko", r"comment-sicko"),
    ("`readonly: true`", r"readonly: (true|false)|readonly/Ask"),
    ('`environment: "cloud"`', r'environment: "(cloud|local)"'),
    ("cloud_base_branch", r"cloud_base_branch"),
    ("`run_in_background: true`", r"run_in_background"),
    ("`resume`", r"`resume`"),
    ("`file_attachments`", r"file_attachments"),
    # 模型选择在这里不成立：具体 slug、别名、规则文件都属于同一件事，
    # 文档只需声明「不按模型选择」，不列举任何一个 slug。
    ("No pstack skill selects a model", r"\b(?:claude|grok|gpt)-[a-z0-9]|inherit-parent|pstack-models\.mdc"),
    (".cursor/skills/", r"\.cursor\/skills"),
    ("~/.cursor/plugins/", r"\.cursor\/plugins|\.cursor-plugin"),
    (".cursor/rules/", r"\.cursor\/rules|always-applied rule"),
    ("agent-transcripts", r"agent-transcripts|\.cursor\/projects"),
    (
        "Cursor-only features",
        r"Bugbot|Cursor [Aa]utomation|cursor\.(sh|com)\/automations|[Cc]loud [Aa]gent|built-in PR tool",
    ),
    # cursor-team-kit 与 Cursor 内建的私有依赖在本机不存在，每项都必须在两份映射表里给出平替。
    ("`deslop`", r"\bdeslop\b"),
    ("`create-skill`", r"\bcreate-skill\b"),
    ("`control-cli`", r"\bcontrol-(?:cli|ui)\b"),
    # 上游用展示名 "Comment Sicko" 作 subagent_type，本机只有小写 slug。
    ("Comment Sicko", r"Comment Sicko"),
]
ROUTE_KEY = "Run another pstack skill"
LINK = re.compile(r"\]\(([^)\s]+)\)")
POINTER = (
    "This skill uses Cursor names. In omp or pi, read {adapter} once per session "
    "before you follow this skill; it maps every Cursor name below to the host you are on."
)


def walk(root):
    for dirpath, _, filenames in os.walk(root):
        for name in sorted(filenames):
            yield os.path.join(dirpath, name)


def skill_dirs(root):
    return sorted(
        name for name in os.listdir(root) if os.path.isfile(os.path.join(root, name, "SKILL.md"))
    )


def skill_text(skill_dir):
    parts = []
    for path in walk(skill_dir):
        if path.endswith(".md"):
            parts.append(open(path, encoding="utf-8").read())
    return "\n".join(parts)


def used_terms(root):
    """返回 {skill: 用到的 Cursor 专名}，含兄弟 skill 的裸引用。"""
    names = skill_dirs(root)
    result = {}
    for name in names:
        text = skill_text(os.path.join(root, name))
        used = {key for key, pattern in TERMS if re.search(pattern, text)}
        others = [other for other in names if other != name]
        for line in text.splitlines():
            if "(../" in line:
                continue
            if any(f"**{other}** skill" in line or f"`/{other}`" in line for other in others):
                used.add(ROUTE_KEY)
                break
        result[name] = used
    return result


def inject_pointer(root, name, adapter_ref):
    """在首个 H1 之后插入指针行；已有标记则跳过。"""
    path = os.path.join(root, name, "SKILL.md")
    text = open(path, encoding="utf-8").read()
    if MARKER in text:
        return False
    match = re.search(r"^# .*$", text, re.MULTILINE)
    if not match:
        return False
    line = POINTER.format(adapter=adapter_ref)
    end = match.end()
    updated = text[:end] + "\n\n" + line + text[end:]
    open(path, "w", encoding="utf-8").write(updated)
    return True


def rewrite_links(root):
    """skills/ 之外的目标在安装后不存在，改写成上游地址。"""
    pstack_root = os.path.dirname(root)
    changed = 0
    for path in walk(root):
        if not path.endswith(".md"):
            continue
        text = open(path, encoding="utf-8").read()

        def replace(match):
            nonlocal changed
            href = match.group(1)
            target = re.sub(r"[#?].*$", "", href)
            if not target or re.match(r"^[a-z][a-z0-9+.-]*:", target, re.IGNORECASE):
                return match.group(0)
            resolved = os.path.normpath(os.path.join(os.path.dirname(path), target))
            if os.path.commonpath([resolved, root]) == root:
                return match.group(0)
            rel = os.path.relpath(resolved, pstack_root)
            # 相对路径跳出 pstack 根，说明链接本来就不成立，保持原样交给上游。
            if rel.startswith(".."):
                return match.group(0)
            kind = "tree" if os.path.isdir(os.path.join(pstack_root, rel)) else "blob"
            suffix = href[len(target):]
            changed += 1
            return f"]({GITHUB}/{kind}/main/pstack/{rel}{suffix})"

        updated = LINK.sub(replace, text)
        if updated != text:
            open(path, "w", encoding="utf-8").write(updated)
    return changed


def main():
    if len(sys.argv) < 3:
        sys.exit("usage: adapt.py <pstack-root> <adapter.md>...")
    root = os.path.abspath(sys.argv[1])
    adapters = [os.path.abspath(path) for path in sys.argv[2:]]
    skills = os.path.join(root, "skills")
    if not os.path.isdir(skills):
        sys.exit(f"缺少 {skills}")

    adapter_text = {}
    for path in adapters:
        adapter_text[path] = open(path, encoding="utf-8").read()
    # 安装后所有 skill 平铺在同一目录，指针用用户级绝对路径，两个 harness 都能读。
    adapter_ref = "`~/.agents/skills/pstack-harness/omp.md` (omp) or `~/.agents/skills/pstack-harness/pi.md` (pi)"

    used = used_terms(skills)
    wrapped = [name for name, terms in used.items() if terms and inject_pointer(skills, name, adapter_ref)]
    rewritten = rewrite_links(skills)

    missing = {}
    for key in sorted({term for terms in used.values() for term in terms}):
        # 术语以连字符结尾（如 `claude-`）时前缀本身即语义，只要求字面出现；
        # 其余按右侧词边界比对，避免 generalPurpose 被 generalPurposeful 误判为已覆盖。
        if key.endswith("-"):
            hit = lambda text: key in text
        else:
            needle = re.compile(rf"(?<![A-Za-z0-9]){re.escape(key)}(?![A-Za-z0-9])")
            hit = needle.search
        uncovered = [os.path.basename(path) for path, text in adapter_text.items() if not hit(text)]
        if uncovered:
            missing[key] = uncovered
    if missing:
        for key, files in missing.items():
            print(f"FAIL 适配文档缺 {key!r}: {', '.join(files)}")
        sys.exit(1)

    print(f"skills={len(used)} wrapped={len(wrapped)} links-rewritten={rewritten} terms={len({t for s in used.values() for t in s})}")
    for name in sorted(wrapped):
        print(f"  wrapped {name}")


if __name__ == "__main__":
    main()
