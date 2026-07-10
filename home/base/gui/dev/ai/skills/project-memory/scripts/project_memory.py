#!/usr/bin/env python3
"""安全检索 Pi 跨 Session 历史的本地 CLI。"""
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

INDEX_NAME = "index-v1.json"
MAX_SNIPPET = 500
MAX_CONTEXT = 3
MAX_SUMMARIES = 2


def now():
    return datetime.now(timezone.utc).isoformat()


def canonical_path(path):
    return str(Path(path).expanduser().resolve())


def git_output(cwd, *args):
    try:
        return subprocess.run(
            ["git", *args], cwd=cwd, text=True, capture_output=True, check=True
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return None


def normalize_remote(url):
    url = url.strip()
    url = re.sub(r"^[a-z]+://", "", url, flags=re.I)
    url = re.sub(r"^[^@/]+@", "", url)
    url = re.sub(r"^([^/]+):", r"\1/", url)
    url = url.rstrip("/")
    if url.endswith(".git"):
        url = url[:-4]
    return url.lower()


def repo_identity(cwd):
    path = Path(cwd).expanduser()
    if not path.exists():
        return None
    root = git_output(str(path), "rev-parse", "--show-toplevel")
    if root:
        remote = git_output(str(path), "remote", "get-url", "origin")
        return normalize_remote(remote) if remote else canonical_path(root)
    return canonical_path(path)


def paths(args):
    return Path(args.sessions_dir).expanduser(), Path(args.cache_dir).expanduser(), Path(args.config_dir).expanduser()


def load_json(path, default, invalid_label=None):
    try:
        return json.loads(path.read_text())
    except FileNotFoundError:
        return default
    except json.JSONDecodeError as error:
        if invalid_label:
            raise ValueError(f"invalid {invalid_label}: {path}: {error.msg}") from error
        return default


def atomic_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", dir=path.parent, delete=False) as handle:
        json.dump(value, handle, ensure_ascii=False, sort_keys=True)
        handle.write("\n")
        temporary = Path(handle.name)
    os.chmod(temporary, 0o600)
    temporary.replace(path)
    os.chmod(path, 0o600)


def index_path(cache):
    return cache / INDEX_NAME


def config_path(config):
    return config / "projects.json"


def load_mapping_data(config):
    data = load_json(config_path(config), {"mappings": {}}, "project mapping")
    if not isinstance(data, dict) or not isinstance(data.get("mappings"), dict):
        raise ValueError(f"invalid project mapping: {config_path(config)}: expected mappings object")
    if not all(isinstance(key, str) and isinstance(value, str) for key, value in data["mappings"].items()):
        raise ValueError(f"invalid project mapping: {config_path(config)}: mappings must contain string pairs")
    return data


def load_mappings(config):
    return load_mapping_data(config)["mappings"]


def read_header(path):
    try:
        with path.open() as handle:
            header = json.loads(handle.readline())
    except (OSError, json.JSONDecodeError) as error:
        return None, f"{path}: invalid session header: {error}"
    if header.get("type") != "session":
        return None, f"{path}: header is not a Pi session"
    required = ("id", "cwd")
    if any(not header.get(key) for key in required):
        return None, f"{path}: session header missing id or cwd"
    return header, None


def session_record(path, mappings, identity_by_cwd):
    header, warning = read_header(path)
    if warning:
        return None, warning
    stat = path.stat()
    cwd = str(header["cwd"])
    if cwd not in identity_by_cwd:
        identity_by_cwd[cwd] = repo_identity(cwd) or mappings.get(cwd)
    identity = identity_by_cwd[cwd]
    return {
        "path": str(path),
        "session_id": str(header["id"]),
        "version": header.get("version"),
        "cwd": cwd,
        "repo_identity": identity,
        "created_at": header.get("timestamp"),
        "updated_at": header.get("timestamp"),
        "size": stat.st_size,
        "mtime_ns": stat.st_mtime_ns,
        "review_status": "unseen",
        "candidate_count": 0,
    }, None


def refresh_index(args, force=False):
    sessions_dir, cache, config = paths(args)
    old = load_json(index_path(cache), {"sessions": []})
    if not isinstance(old, dict) or not isinstance(old.get("sessions"), list):
        old = {"sessions": []}
    old_records = {str(Path(item["path"]).resolve()): item for item in old["sessions"] if isinstance(item, dict) and "path" in item}
    mappings = load_mappings(config)
    warnings = []
    records = []
    identity_by_cwd = {}
    if sessions_dir.exists():
        files = sorted(sessions_dir.rglob("*.jsonl"))
    else:
        files = []
        warnings.append(f"sessions directory does not exist: {sessions_dir}")
    for file in files:
        resolved = str(file.resolve())
        stat = file.stat()
        existing = old_records.get(resolved)
        if not force and existing and existing.get("repo_identity") and existing.get("size") == stat.st_size and existing.get("mtime_ns") == stat.st_mtime_ns:
            records.append(existing)
            continue
        record, warning = session_record(file, mappings, identity_by_cwd)
        if warning:
            warnings.append(warning)
            continue
        if existing:
            for key in ("review_status", "reviewed_mtime_ns", "reviewed_at", "candidate_count"):
                if key in existing:
                    record[key] = existing[key]
        records.append(record)
    payload = {"version": 1, "sessions": records}
    atomic_json(index_path(cache), payload)
    return payload, warnings


def derived_status(record):
    reviewed = record.get("reviewed_mtime_ns")
    if reviewed is not None and reviewed != record["mtime_ns"]:
        return "changed"
    return record.get("review_status", "unseen")


def current_identity(args):
    identity = repo_identity(args.project_dir)
    if identity is None:
        raise ValueError(f"project directory no longer exists: {args.project_dir}")
    return identity


def scoped_records(args, payload, all_projects=False):
    identity = current_identity(args)
    records = [item for item in payload["sessions"] if item.get("repo_identity")]
    if not all_projects:
        records = [item for item in records if item["repo_identity"] == identity]
    return records, identity


def output(value):
    json.dump(value, sys.stdout, ensure_ascii=False, sort_keys=True)
    sys.stdout.write("\n")


def read_entries(record):
    entries, warnings = [], []
    try:
        lines = Path(record["path"]).read_text().splitlines()[1:]
    except OSError as error:
        return [], [f"{record['path']}: cannot read session: {error}"]
    for number, line in enumerate(lines, start=2):
        try:
            item = json.loads(line)
        except json.JSONDecodeError as error:
            warnings.append(f"{record['path']}: invalid JSONL line {number}: {error.msg}")
            continue
        if not isinstance(item, dict) or not item.get("id"):
            warnings.append(f"{record['path']}: invalid entry at line {number}")
            continue
        entries.append(item)
    return entries, warnings


def text_value(value):
    if isinstance(value, str):
        return value
    if isinstance(value, list):
        return " ".join(text_value(item.get("text", item.get("content", ""))) if isinstance(item, dict) else text_value(item) for item in value)
    if isinstance(value, dict):
        return text_value(value.get("text", value.get("content", "")))
    return ""


def message_text(content):
    if isinstance(content, str):
        return content
    if not isinstance(content, list):
        return text_value(content)
    return " ".join(
        text_value(item)
        for item in content
        if not isinstance(item, dict) or item.get("type") in {None, "text"}
    )


def tool_call_text(content):
    if not isinstance(content, list):
        return ""
    calls = []
    for item in content:
        if not isinstance(item, dict) or item.get("type") != "toolCall":
            continue
        arguments = json.dumps(item.get("arguments", {}), ensure_ascii=False, sort_keys=True)
        calls.append(f"{item.get('name', '')} {arguments}".strip())
    return " ".join(calls)


def entry_details(entry, include_tools=False):
    kind = entry.get("type", "unknown")
    if kind in {"compaction", "branch_summary", "summary"}:
        text = text_value(entry.get("summary", entry.get("content", "")))
        return [("summary", "summary", text, False)] if text else []

    message = entry.get("message") if isinstance(entry.get("message"), dict) else {}
    role = message.get("role", entry.get("role", ""))
    content = message.get("content", entry.get("content", ""))
    if kind in {"tool", "tool_call", "tool_result"}:
        text = text_value(entry.get("content", entry.get("result", entry.get("arguments", ""))))
        return [(role or "tool", "tool", text, False)] if include_tools and text else []
    if role == "toolResult":
        text = " ".join(part for part in (str(message.get("toolName", "")), message_text(content)) if part)
        return [(role, "tool", text, False)] if include_tools and text else []
    if role == "user":
        text = message_text(content)
        return [(role, "message", text, True)] if text else []
    if role == "assistant":
        details = []
        text = message_text(content)
        if text:
            details.append((role, "message", text, True))
        calls = tool_call_text(content)
        if include_tools and calls:
            details.append((role, "tool", calls, False))
        return details
    return []


def lineage(entries, leaf_id=None):
    by_id = {str(item["id"]): item for item in entries}
    if not by_id:
        return []
    current = str(leaf_id or entries[-1]["id"])
    result = []
    seen = set()
    while current in by_id and current not in seen:
        seen.add(current)
        result.append(by_id[current])
        parent = by_id[current].get("parentId")
        if parent is None:
            break
        current = str(parent)
    result.reverse()
    return result


def active_ids(entries):
    return {str(item["id"]) for item in lineage(entries)}


def redact(text):
    text = re.sub(r"-----BEGIN [^-]+ PRIVATE KEY-----.*?-----END [^-]+ PRIVATE KEY-----", "[REDACTED PRIVATE KEY]", text, flags=re.I | re.S)
    text = re.sub(r"(?i)(authorization\s*:\s*(?:bearer|basic)\s+)\S+", r"\1[REDACTED]", text)
    text = re.sub(r"(?i)(authorization\s*:\s*)\S+", r"\1[REDACTED]", text)
    text = re.sub(r"(?i)\b(bearer\s+)[A-Za-z0-9._~+/-]+", r"\1[REDACTED]", text)
    text = re.sub(r"(?i)\b(set-cookie|cookie)\s*:\s*[^\r\n]+", r"\1: [REDACTED]", text)
    text = re.sub(
        r"(?i)([\"']?(?:api[_-]?key|token|secret|password|cookie)[\"']?\s*[:=]\s*)([\"']).*?\2",
        r"\1[REDACTED]",
        text,
    )
    text = re.sub(r"(?i)\b(api[_-]?key|token|secret|password|cookie)\s*([:=])\s*[^\s,;]+", r"\1\2[REDACTED]", text)
    return text[:MAX_SNIPPET]


def search_items(record, query, include_tools, all_branches):
    entries, warnings = read_entries(record)
    active = active_ids(entries)
    terms = query.lower().split()
    matches = []
    for order, entry in enumerate(entries):
        is_active = str(entry["id"]) in active
        if not is_active and not all_branches:
            continue
        branch = "active" if is_active else "abandoned"
        best = None
        for role, kind, text, evidence in entry_details(entry, include_tools):
            lowered = text.lower()
            hits = sum(term in lowered for term in terms)
            if not hits:
                continue
            phrase = query.lower() in lowered
            score = hits * 100 + (50 if phrase else 0) + (20 if role == "user" else 10 if role == "assistant" else 0) - (30 if branch == "abandoned" else 0) - (10 if kind == "tool" else 0)
            item = {"result_id": f"{record['session_id']}:{entry['id']}", "session_id": record["session_id"], "entry_id": str(entry["id"]), "timestamp": entry.get("timestamp"), "role": role, "kind": kind, "branch_status": branch, "evidence": evidence, "snippet": redact(text)}
            if best is None or score > best[0]:
                best = (score, order, item)
        if best is not None:
            matches.append(best)
    return matches, warnings


def command_search(args):
    args.query = args.query.strip()
    if not args.query:
        raise ValueError("query must not be empty")
    payload, warnings = refresh_index(args)
    records, identity = scoped_records(args, payload, args.all_projects)
    matches = []
    for record in records:
        items, item_warnings = search_items(record, args.query, args.include_tools, args.all_branches)
        warnings.extend(item_warnings)
        matches.extend(items)
    matches.sort(key=lambda item: (-item[0], item[1], item[2]["result_id"]))
    by_session, results = {}, []
    for _, _, item in matches:
        bucket = by_session.setdefault(item["session_id"], 0)
        if bucket >= 3 or len({result["session_id"] for result in results}) >= args.limit and item["session_id"] not in {result["session_id"] for result in results}:
            continue
        by_session[item["session_id"]] += 1
        results.append(item)
    output({"project_identity": identity, "results": results, "warnings": warnings})


def command_show(args):
    if ":" not in args.result_id:
        raise ValueError("result_id must be SESSION_ID:ENTRY_ID")
    session_id, entry_id = args.result_id.split(":", 1)
    payload, warnings = refresh_index(args)
    records, _ = scoped_records(args, payload, all_projects=args.all_projects)
    record = next((item for item in records if item["session_id"] == session_id), None)
    if record is None:
        raise ValueError(f"session not found in selected project scope: {session_id}")
    entries, item_warnings = read_entries(record)
    warnings.extend(item_warnings)
    active = active_ids(entries)
    target = next((item for item in entries if str(item["id"]) == entry_id), None)
    if target is None:
        raise ValueError(f"entry not found: {entry_id}")
    is_active = entry_id in active
    if not is_active and not args.all_branches:
        raise ValueError(f"entry is outside active lineage; use --all-branches: {entry_id}")
    selected = lineage(entries) if is_active else lineage(entries, entry_id)
    target_index = next(index for index, item in enumerate(selected) if str(item["id"]) == entry_id)
    context = []
    for entry in selected[max(0, target_index - MAX_CONTEXT):target_index + MAX_CONTEXT + 1]:
        branch_status = "active" if str(entry["id"]) in active else "abandoned"
        for role, kind, text, evidence in entry_details(entry, args.include_tools):
            context.append({"entry_id": str(entry["id"]), "timestamp": entry.get("timestamp"), "role": role, "kind": kind, "branch_status": branch_status, "evidence": evidence, "snippet": redact(text)})
    output({"result_id": args.result_id, "session_id": session_id, "entry_id": entry_id, "context": context, "warnings": warnings})


def command_mine(args):
    payload, warnings = refresh_index(args)
    records, identity = scoped_records(args, payload)
    eligible = [record for record in records if args.include_reviewed or derived_status(record) in {"unseen", "changed"}]
    eligible.sort(key=lambda record: record["mtime_ns"], reverse=True)
    triage = []
    for record in eligible[:args.limit]:
        entries, item_warnings = read_entries(record)
        warnings.extend(item_warnings)
        active = active_ids(entries)
        items = []
        for entry in entries:
            if str(entry["id"]) not in active:
                continue
            for role, kind, text, evidence in entry_details(entry):
                if role not in {"user", "assistant", "summary"}:
                    continue
                items.append({"entry_id": str(entry["id"]), "timestamp": entry.get("timestamp"), "role": role, "kind": kind, "evidence": evidence, "snippet": redact(text)})
        summaries = [item for item in items if item["kind"] == "summary"][-MAX_SUMMARIES:]
        messages = [item for item in items if item["kind"] == "message"][-3:]
        triage.append({"session_id": record["session_id"], "status": derived_status(record), "items": summaries + messages})
    output({"project_identity": identity, "sessions": triage, "warnings": warnings})


def command_mark_reviewed(args):
    payload, warnings = refresh_index(args)
    records, _ = scoped_records(args, payload)
    record = next((item for item in records if item["session_id"] == args.session_id), None)
    if record is None:
        raise ValueError(f"session not found in current project: {args.session_id}")
    record.update({"review_status": args.status, "reviewed_mtime_ns": record["mtime_ns"], "reviewed_at": now(), "candidate_count": args.candidate_count})
    _, cache, _ = paths(args)
    atomic_json(index_path(cache), payload)
    output({"session_id": args.session_id, "status": args.status, "candidate_count": args.candidate_count, "warnings": warnings})


def command_map_project(args):
    payload, warnings = refresh_index(args)
    identity = current_identity(args)
    record = next((item for item in payload["sessions"] if item["session_id"] == args.target or item["cwd"] == args.target), None)
    old_cwd = record["cwd"] if record else args.target
    _, _, config = paths(args)
    data = load_mapping_data(config)
    mappings = data["mappings"]
    mappings[old_cwd] = identity
    atomic_json(config_path(config), data)
    refresh_index(args)
    output({"mapped": old_cwd, "repo_identity": identity, "warnings": warnings})


def command_rebuild(args):
    payload, warnings = refresh_index(args, force=True)
    unresolved = sum(1 for record in payload["sessions"] if not record.get("repo_identity"))
    output({"indexed": len(payload["sessions"]), "unresolved": unresolved, "warnings": warnings})


def command_status(args):
    payload, warnings = refresh_index(args)
    records, identity = scoped_records(args, payload)
    counts = {name: 0 for name in ("unseen", "reviewed", "pending", "resolved", "changed")}
    for record in records:
        counts[derived_status(record)] += 1
    unresolved = sum(1 for record in payload["sessions"] if not record.get("repo_identity"))
    output({"project_identity": identity, "sessions": len(records), "unresolved": unresolved, "warnings": warnings, **counts})


def positive_int(value):
    number = int(value)
    if number < 1:
        raise argparse.ArgumentTypeError("must be at least 1")
    return number


def non_negative_int(value):
    number = int(value)
    if number < 0:
        raise argparse.ArgumentTypeError("must be at least 0")
    return number


def parser():
    defaults = {
        "sessions": str(Path.home() / ".pi/agent/sessions"),
        "cache": str(Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "project-memory"),
        "config": str(Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "project-memory"),
    }
    result = argparse.ArgumentParser()
    result.add_argument("--sessions-dir", default=defaults["sessions"])
    result.add_argument("--cache-dir", default=defaults["cache"])
    result.add_argument("--config-dir", default=defaults["config"])
    result.add_argument("--project-dir", default=os.getcwd())
    sub = result.add_subparsers(dest="command", required=True)
    sub.add_parser("rebuild-index")
    sub.add_parser("status")
    search = sub.add_parser("search")
    search.add_argument("query")
    search.add_argument("--all-projects", action="store_true")
    search.add_argument("--all-branches", action="store_true")
    search.add_argument("--include-tools", action="store_true")
    search.add_argument("--limit", type=positive_int, default=5)
    show = sub.add_parser("show")
    show.add_argument("result_id")
    show.add_argument("--all-projects", action="store_true")
    show.add_argument("--all-branches", action="store_true")
    show.add_argument("--include-tools", action="store_true")
    mine = sub.add_parser("mine")
    mine.add_argument("--limit", type=positive_int, default=5)
    mine.add_argument("--include-reviewed", action="store_true")
    mark = sub.add_parser("mark-reviewed")
    mark.add_argument("session_id")
    mark.add_argument("--status", choices=("reviewed", "pending", "resolved"), required=True)
    mark.add_argument("--candidate-count", type=non_negative_int, default=0)
    mapping = sub.add_parser("map-project")
    mapping.add_argument("target")
    mapping.add_argument("--to-current", action="store_true", required=True)
    return result


def main():
    args = parser().parse_args()
    try:
        {"rebuild-index": command_rebuild, "status": command_status, "search": command_search, "show": command_show, "mine": command_mine, "mark-reviewed": command_mark_reviewed, "map-project": command_map_project}[args.command](args)
    except (ValueError, OSError) as error:
        print(f"project-memory: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
