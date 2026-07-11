#!/usr/bin/env python3
"""安全检索 Pi 跨 Session 历史的本地 CLI。"""
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import unicodedata
from datetime import datetime, timedelta, timezone
from difflib import SequenceMatcher
from pathlib import Path

INDEX_NAME = "index-v1.json"
MAX_SNIPPET = 500
MAX_CONTEXT = 3
MAX_SUMMARIES = 2
REPEATED_PROMPT_THRESHOLD = 0.86
CORRECTION_MARKERS = (
    "不对",
    "不是这个",
    "完全错误",
    "我已经说过",
    "你又",
    "还是没有",
    "wrong",
    "already said",
    "you ignored",
)


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


def select_session(records, selector):
    exact = next((record for record in records if record["session_id"] == selector), None)
    if exact is not None:
        return exact
    recent = sorted(records, key=lambda record: record["mtime_ns"], reverse=True)
    if selector == "latest":
        if recent:
            return recent[0]
        raise ValueError("no sessions in selected project scope")
    if selector == "previous":
        if len(recent) >= 2:
            return recent[1]
        raise ValueError("no previous session in selected project scope")
    matches = [record for record in records if record["session_id"].startswith(selector)]
    if len(matches) == 1:
        return matches[0]
    if not matches:
        raise ValueError(f"session not found in selected project scope: {selector}")
    raise ValueError(f"session selector is ambiguous: {selector}")


def select_entry(entries, selector):
    active = lineage(entries)
    if selector == "last":
        if active:
            return active[-1]
    elif selector in {"last-user", "last-assistant"}:
        role = selector.removeprefix("last-")
        for entry in reversed(active):
            if any(item_role == role for item_role, _, _, _ in entry_details(entry)):
                return entry
    else:
        target = next((entry for entry in entries if str(entry["id"]) == selector), None)
        if target is not None:
            return target
    raise ValueError(f"entry not found: {selector}")


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


def transcript_items(entries, all_branches=False, for_signals=False):
    items = []
    active = active_ids(entries)
    selected = entries if all_branches else lineage(entries)
    for entry in selected:
        kind = entry.get("type", "unknown")
        if kind in {"compaction", "branch_summary", "summary"}:
            text = text_value(entry.get("summary", entry.get("content", "")))
            if text:
                items.append({"entry_id": str(entry["id"]), "timestamp": entry.get("timestamp"), "role": "summary", "kind": "summary", "branch_status": "active" if str(entry["id"]) in active else "abandoned", "evidence": False, "is_error": False, "snippet": redact(text)})
            continue
        message = entry.get("message") if isinstance(entry.get("message"), dict) else {}
        role = message.get("role", entry.get("role", ""))
        content = message.get("content", entry.get("content", ""))
        evidence = role in {"user", "assistant"}
        is_error = bool(message.get("isError")) or (role == "assistant" and message.get("stopReason") == "error")
        if role == "assistant":
            parts = [tool_call_text(content), message_text(content)]
            if is_error:
                parts.append(text_value(message.get("errorMessage", "")) or "assistant stopped with error")
            text = "\n".join(part for part in parts if part)
            item_kind = "message"
        elif role == "toolResult":
            text = " ".join(part for part in (str(message.get("toolName", "")), message_text(content)) if part)
            item_kind = "tool"
        elif role == "bashExecution":
            text = "\n".join(part for part in (str(message.get("command", "")), str(message.get("output", ""))) if part)
            item_kind = "tool"
            exit_code = message.get("exitCode")
            is_error = is_error or bool(message.get("cancelled")) or (isinstance(exit_code, int) and exit_code != 0)
        elif role == "user":
            text = message_text(content)
            item_kind = "message"
        else:
            continue
        if text:
            item = {"entry_id": str(entry["id"]), "timestamp": entry.get("timestamp"), "role": role, "kind": item_kind, "branch_status": "active" if str(entry["id"]) in active else "abandoned", "evidence": evidence, "is_error": is_error, "snippet": redact(text, truncate=not for_signals)}
            if for_signals:
                item["_parent_id"] = str(entry.get("parentId", ""))
            items.append(item)
    return items


def episode(items, indexes, radius=2):
    selected = set()
    branches = {items[index]["branch_status"] for index in indexes}
    for index in indexes:
        selected.update(range(max(0, index - radius), min(len(items), index + radius + 1)))
    result = []
    for index, item in enumerate(items):
        if index not in selected or item["branch_status"] not in branches:
            continue
        public_item = {key: value for key, value in item.items() if not key.startswith("_")}
        public_item["snippet"] = redact(public_item["snippet"])
        result.append(public_item)
    return result


def normalized_prompt(text):
    normalized = unicodedata.normalize("NFKC", text).casefold()
    return re.sub(r"[^\w]+", "", normalized, flags=re.UNICODE)


def prompt_similarity(previous, current):
    if previous == current:
        return 1.0
    if max(len(previous), len(current)) > MAX_SNIPPET:
        return 0.0
    return SequenceMatcher(None, previous, current).ratio()


def problem_signals(items):
    signals = []
    error_number = 0
    index = 0
    while index < len(items):
        if not items[index]["is_error"]:
            index += 1
            continue
        indexes = [index]
        while indexes[-1] + 1 < len(items):
            previous = items[indexes[-1]]
            current = items[indexes[-1] + 1]
            if not (
                current["is_error"]
                and current["branch_status"] == previous["branch_status"]
                and current.get("_parent_id") == previous["entry_id"]
            ):
                break
            indexes.append(indexes[-1] + 1)
        error_number += 1
        signals.append({
            "signal_id": f"command_failure:{error_number}",
            "kind": "command_failure",
            "score": 2,
            "entry_ids": [items[item_index]["entry_id"] for item_index in indexes],
            "episode": episode(items, indexes),
        })
        index = indexes[-1] + 1

    user_indexes = [index for index, item in enumerate(items) if item["role"] == "user"]
    repeat_number = 0
    for position, current_index in enumerate(user_indexes):
        current = normalized_prompt(items[current_index]["snippet"])
        if len(current) < 8:
            continue
        best = None
        for previous_index in user_indexes[:position]:
            if items[previous_index]["branch_status"] != items[current_index]["branch_status"]:
                continue
            previous = normalized_prompt(items[previous_index]["snippet"])
            if len(previous) < 8:
                continue
            similarity = prompt_similarity(previous, current)
            if best is None or similarity > best[0]:
                best = (similarity, previous_index)
        if best is None or best[0] < REPEATED_PROMPT_THRESHOLD:
            continue
        repeat_number += 1
        indexes = [best[1], current_index]
        signals.append({
            "signal_id": f"repeated_user_prompt:{repeat_number}",
            "kind": "repeated_user_prompt",
            "score": 3,
            "entry_ids": [items[item_index]["entry_id"] for item_index in indexes],
            "similarity": round(best[0], 2),
            "episode": episode(items, indexes, radius=1),
        })

    correction_number = 0
    items_by_id = {item["entry_id"]: item for item in items}
    for index, item in enumerate(items):
        parent = items_by_id.get(item.get("_parent_id"))
        if item["role"] != "user" or parent is None or parent["role"] != "assistant":
            continue
        lowered = item["snippet"].casefold()
        if any(marker in lowered for marker in CORRECTION_MARKERS):
            correction_number += 1
            signals.append({
                "signal_id": f"user_correction:{correction_number}",
                "kind": "user_correction",
                "score": 3,
                "entry_ids": [item["entry_id"]],
                "episode": episode(items, [index]),
            })
    return signals


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


def redact(text, truncate=True):
    text = re.sub(r"-----BEGIN [^-]+ PRIVATE KEY-----.*?-----END [^-]+ PRIVATE KEY-----", "[REDACTED PRIVATE KEY]", text, flags=re.I | re.S)
    text = re.sub(r"(?i)(authorization\s*:\s*(?:bearer|basic)\s+)\S+", r"\1[REDACTED]", text)
    text = re.sub(r'''(?i)(["']?authorization["']?\s*:\s*["']?(?:bearer|basic)\s+)[^"'\s,;}]+''', r"\1[REDACTED]", text)
    text = re.sub(r"(?i)(authorization\s*:\s*)\S+", r"\1[REDACTED]", text)
    text = re.sub(r"(?i)\b(bearer\s+)[A-Za-z0-9._~+/-]+", r"\1[REDACTED]", text)
    text = re.sub(r"(?i)\b(set-cookie|cookie)\s*:\s*[^\r\n]+", r"\1: [REDACTED]", text)
    text = re.sub(
        r"(?i)([\"']?(?:api[_-]?key|token|secret|password|cookie)[\"']?\s*[:=]\s*)([\"']).*?\2",
        r"\1[REDACTED]",
        text,
    )
    text = re.sub(r"(?i)\b(api[_-]?key|token|secret|password|cookie)\s*([:=])\s*[^\s,;]+", r"\1\2[REDACTED]", text)
    return text[:MAX_SNIPPET] if truncate else text


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
    if args.session:
        records = [select_session(records, args.session)]
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
    if args.transcript:
        if args.result_id or args.entry or not args.session:
            raise ValueError("--transcript requires --session and cannot be combined with RESULT_ID or --entry")
        payload, warnings = refresh_index(args)
        records, _ = scoped_records(args, payload, all_projects=args.all_projects)
        record = select_session(records, args.session)
        entries, item_warnings = read_entries(record)
        warnings.extend(item_warnings)
        output({"session_id": record["session_id"], "transcript": transcript_items(entries, args.all_branches), "warnings": warnings})
        return
    if args.result_id:
        if args.session or args.entry:
            raise ValueError("result_id cannot be combined with --session or --entry")
        if ":" not in args.result_id:
            raise ValueError("result_id must be SESSION_ID:ENTRY_ID")
        session_id, entry_id = args.result_id.split(":", 1)
    else:
        if not args.session:
            raise ValueError("show requires RESULT_ID or --session")
        session_id = None
        entry_id = args.entry or "last"
    payload, warnings = refresh_index(args)
    records, _ = scoped_records(args, payload, all_projects=args.all_projects)
    if session_id is None:
        record = select_session(records, args.session)
        session_id = record["session_id"]
    else:
        record = next((item for item in records if item["session_id"] == session_id), None)
        if record is None:
            raise ValueError(f"session not found in selected project scope: {session_id}")
    entries, item_warnings = read_entries(record)
    warnings.extend(item_warnings)
    active = active_ids(entries)
    if args.result_id:
        target = next((item for item in entries if str(item["id"]) == entry_id), None)
        if target is None:
            raise ValueError(f"entry not found: {entry_id}")
    else:
        target = select_entry(entries, entry_id)
        entry_id = str(target["id"])
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
    output({"result_id": f"{session_id}:{entry_id}", "session_id": session_id, "entry_id": entry_id, "context": context, "warnings": warnings})


def parse_time_bound(value, end_of_day=False):
    if value is None:
        return None
    relative = re.fullmatch(r"(\d+)d", value)
    if relative:
        parsed = datetime.now(timezone.utc) - timedelta(days=int(relative.group(1)))
        return int(parsed.timestamp() * 1_000_000_000)
    date_only = re.fullmatch(r"\d{4}-\d{2}-\d{2}", value)
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as error:
        raise ValueError(f"invalid time bound: {value}; use Nd or ISO 8601") from error
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    if end_of_day and date_only:
        parsed += timedelta(days=1)
        return int(parsed.timestamp() * 1_000_000_000) - 1
    return int(parsed.timestamp() * 1_000_000_000)


def output_mine_ndjson(identity, sessions, warnings):
    output({"type": "meta", "project_identity": identity})
    for session in sessions:
        session_id = session["session_id"]
        header = {"type": "session", "session_id": session_id, "status": session["status"]}
        if "signals" in session:
            header.update({"problem_score": session["problem_score"], "signal_counts": session["signal_counts"]})
            output(header)
            for signal in session["signals"]:
                output({"type": "signal", "session_id": session_id, **signal})
            continue
        output(header)
        key, item_type = ("transcript", "transcript") if "transcript" in session else ("items", "item")
        for item in session[key]:
            output({"type": item_type, "session_id": session_id, **item})
    for warning in warnings:
        output({"type": "warning", "message": warning})


def command_mine(args):
    payload, warnings = refresh_index(args)
    records, identity = scoped_records(args, payload)
    since = parse_time_bound(args.since)
    until = parse_time_bound(args.until, end_of_day=True)
    if since is not None and until is not None and since > until:
        raise ValueError("--since must not be later than --until")
    eligible = [record for record in records if args.include_reviewed or derived_status(record) in {"unseen", "changed"}]
    if since is not None:
        eligible = [record for record in eligible if record["mtime_ns"] >= since]
    if until is not None:
        eligible = [record for record in eligible if record["mtime_ns"] <= until]
    eligible.sort(key=lambda record: record["mtime_ns"], reverse=True)
    triage = []
    selected_records = eligible if args.signals else eligible[:args.limit]
    for record in selected_records:
        entries, item_warnings = read_entries(record)
        warnings.extend(item_warnings)
        if args.signals:
            signals = problem_signals(transcript_items(entries, args.all_branches, for_signals=True))
            if not signals:
                continue
            counts = {kind: sum(signal["kind"] == kind for signal in signals) for kind in ("command_failure", "repeated_user_prompt", "user_correction")}
            triage.append({
                "session_id": record["session_id"],
                "status": derived_status(record),
                "problem_score": sum(signal["score"] for signal in signals),
                "signal_counts": {kind: count for kind, count in counts.items() if count},
                "signals": signals,
                "mtime_ns": record["mtime_ns"],
            })
            continue
        if args.transcript:
            triage.append({"session_id": record["session_id"], "status": derived_status(record), "transcript": transcript_items(entries, args.all_branches)})
            continue
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
    if args.signals:
        triage.sort(key=lambda session: (-session["problem_score"], -session["mtime_ns"]))
        triage = triage[:args.limit]
        for session in triage:
            session.pop("mtime_ns")
    if args.format == "ndjson":
        output_mine_ndjson(identity, triage, warnings)
    else:
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
    search.add_argument("--session")
    show = sub.add_parser("show")
    show.add_argument("result_id", nargs="?")
    show.add_argument("--session")
    show.add_argument("--entry")
    show.add_argument("--transcript", action="store_true")
    show.add_argument("--all-projects", action="store_true")
    show.add_argument("--all-branches", action="store_true")
    show.add_argument("--include-tools", action="store_true")
    mine = sub.add_parser("mine")
    mine.add_argument("--limit", type=positive_int, default=5)
    mine.add_argument("--since")
    mine.add_argument("--until")
    mine.add_argument("--include-reviewed", action="store_true")
    mine_view = mine.add_mutually_exclusive_group()
    mine_view.add_argument("--transcript", action="store_true")
    mine_view.add_argument("--signals", action="store_true")
    mine.add_argument("--all-branches", action="store_true")
    mine.add_argument("--format", choices=("json", "ndjson"), default="json")
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
