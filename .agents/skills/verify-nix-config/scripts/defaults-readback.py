#!/usr/bin/env python3

import argparse
import json
import os
import plistlib
import re
import subprocess
import sys
import tempfile

WRITE_PATTERN = re.compile(r"defaults write (\S+) (\S+) '(<\?xml.*?</plist>)'", re.S)


def parse_writes(activate_path):
    text = open(activate_path, encoding="utf-8").read()
    writes = []
    for domain, key, xml in WRITE_PATTERN.findall(text):
        writes.append({"domain": domain, "key": key, "expected": plistlib.loads(xml.encode())})
    return writes


def export_domain(domain):
    with tempfile.TemporaryDirectory(prefix="defaults-readback.") as scratch:
        target = os.path.join(scratch, "domain.plist")
        result = subprocess.run(
            ["/usr/bin/defaults", "export", domain, target],
            capture_output=True,
            text=True,
        )
        if result.returncode != 0 or not os.path.exists(target):
            return None, (result.stderr.strip() or "defaults export failed")
        try:
            with open(target, "rb") as handle:
                return plistlib.load(handle), None
        except Exception as error:
            return None, str(error)


def compare(expected, actual):
    if expected == actual and type(expected) is type(actual):
        return "match"
    if expected == actual:
        return "type_differs"
    return "mismatch"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("activate", help="path to the generated activate script")
    parser.add_argument("--output", help="write the full JSON report to this path")
    args = parser.parse_args()

    if not os.path.isfile(args.activate):
        print(f"defaults-readback: no activate script at {args.activate}", file=sys.stderr)
        return 2

    writes = parse_writes(args.activate)
    if not writes:
        print(f"defaults-readback: no defaults write statements in {args.activate}", file=sys.stderr)
        return 2

    contents = {}
    for write in writes:
        domain = write["domain"]
        if domain not in contents:
            contents[domain] = export_domain(domain)

    report = []
    for write in writes:
        domain, key = write["domain"], write["key"]
        stored, error = contents[domain]
        if stored is None:
            status, actual = "unreadable", None
        elif key not in stored:
            status, actual = "missing", None
        else:
            actual = stored[key]
            status = compare(write["expected"], actual)
        report.append({**write, "actual": actual, "status": status})

    counts = {}
    for entry in report:
        counts[entry["status"]] = counts.get(entry["status"], 0) + 1

    failed = [e for e in report if e["status"] in ("mismatch", "missing", "unreadable")]
    for entry in failed:
        print(
            f"{entry['status']:<10} {entry['domain']} {entry['key']}: "
            f"declared={entry['expected']!r} actual={entry['actual']!r}",
            file=sys.stderr,
        )
    typed = [e for e in report if e["status"] == "type_differs"]
    for entry in typed:
        print(
            f"type_differs {entry['domain']} {entry['key']}: "
            f"declared={entry['expected']!r} ({type(entry['expected']).__name__}) "
            f"stored={entry['actual']!r} ({type(entry['actual']).__name__})",
            file=sys.stderr,
        )

    summary = {
        "activate": args.activate,
        "total": len(report),
        "counts": counts,
    }
    if args.output:
        with open(args.output, "w", encoding="utf-8") as handle:
            json.dump({"summary": summary, "entries": report}, handle, ensure_ascii=False, indent=2)

    print(json.dumps(summary, ensure_ascii=False))
    print(
        f"match={counts.get('match', 0)} type_differs={counts.get('type_differs', 0)} "
        f"mismatch={counts.get('mismatch', 0)} missing={counts.get('missing', 0)} "
        f"unreadable={counts.get('unreadable', 0)}",
        file=sys.stderr,
    )
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
