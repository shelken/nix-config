#!/usr/bin/env python3
"""并发探测各主机是否落后于 origin/main（只读）。

对每台主机比较两个系统路径：
- 期望：origin/main 下求值出的系统 outPath（只求值，不构建）
- 实际：主机上 /run/current-system 指向的路径（SSH 读取；本机直接读本地）

判定语义是「部署 origin/main 会不会改变这台机器」：路径相同为最新，不同为待部署。
因此不能给系统加 configurationRevision，否则每次提交都会让所有主机的路径变化。

主机名单取自 flake 的 deploy.nodes，再加上本机（.host-profile 里的 PROFILE）。
离线或过慢的主机在 --timeout 秒内标为不可达，不拖住其他主机。
退出码：全部最新为 0，否则为 1，参数错误为 2。
"""
import argparse
import json
import os
import re
import subprocess
import sys
import time
import unicodedata
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from pathlib import Path

# 配置类别 → 每台主机要求值的属性路径
KINDS = {
    "nixosConfigurations": "config.system.build.toplevel.outPath",
    "darwinConfigurations": "system.outPath",
}

# 从 stdin 喂给 sh，不依赖远端登录 shell。GNU stat 存在时不会走到 BSD 的 -f 分支
PROBE_SCRIPT = """\
cur=$(readlink /run/current-system) || exit 1
t=$(stat -c %Y /nix/var/nix/profiles/system 2>/dev/null || stat -f %m /nix/var/nix/profiles/system)
reboot=-
if [ -e /run/booted-system ]; then
  reboot=no
  for f in kernel initrd kernel-modules; do
    [ "$(readlink /run/booted-system/$f)" = "$(readlink /run/current-system/$f)" ] || reboot=yes
  done
fi
echo "$cur $t $reboot"
"""

UP_TO_DATE, BEHIND, UNREACHABLE, EVAL_FAILED = "最新", "待部署", "不可达", "求值失败"
STATES = (UP_TO_DATE, BEHIND, UNREACHABLE, EVAL_FAILED)
HEADER = ("主机", "状态", "上次切换", "需重启", "说明")
REBOOT_TEXT = {"yes": "是", "no": "否"}


def parse_probe(line: str) -> tuple[str, int, str]:
    """解析探测脚本的输出 `<路径> <mtime> <yes|no|->`"""
    fields = line.split()
    if len(fields) != 3:
        raise ValueError(f"探测输出格式不对：{line!r}")
    path, mtime, reboot = fields
    return path, int(mtime), reboot


def classify(expected: str | None, eval_error: str | None, probe: tuple | None, probe_error: str | None) -> str:
    """求值失败优先于不可达：期望路径都没有，探测结果无从比较"""
    if eval_error:
        return EVAL_FAILED
    if probe_error:
        return UNREACHABLE
    return UP_TO_DATE if probe[0] == expected else BEHIND


def error_summary(stderr: str) -> str:
    """取最后一个 `error:` 起的文字：断言失败时消息在 `error:` 之后的多行里"""
    lines = [line.strip() for line in stderr.strip().splitlines() if line.strip()]
    starts = [i for i, line in enumerate(lines) if line.startswith("error:")]
    return " ".join(lines[starts[-1] :]) if starts else (lines[-1] if lines else "nix eval 失败")


def run(cmd: list[str], **kwargs) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, **kwargs)


def git(*args: str) -> str:
    result = run(["git", *args])
    if result.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)} 失败：{result.stderr.strip()}")
    return result.stdout.strip()


def resolve_flake(args: argparse.Namespace) -> tuple[str, str]:
    """返回 (flake ref, 基准说明)；固定到 origin/main 的 rev，不混入工作区里未提交的改动"""
    if args.flake:
        return args.flake, f"基准: {args.flake}"
    if not args.no_fetch:
        fetched = run(["git", "fetch", "--quiet", "origin", "main"])
        if fetched.returncode != 0:
            print(f"警告：git fetch 失败，使用本地已有的 origin/main：{error_summary(fetched.stderr)}", file=sys.stderr)
    rev = git("rev-parse", "origin/main")
    root = git("rev-parse", "--show-toplevel")
    return f"git+file://{root}?rev={rev}", f"基准: origin/main {rev[:8]}"


def local_profile() -> str | None:
    if os.environ.get("PROFILE"):
        return os.environ["PROFILE"]
    profile_file = Path(git("rev-parse", "--show-toplevel")) / ".host-profile"
    if profile_file.is_file():
        match = re.search(r"^PROFILE=(\S+)", profile_file.read_text(), re.M)
        return match.group(1) if match else None
    return None


def nix_json(flake: str, attr: str, apply: str):
    result = run(["nix", "eval", "--json", f"{flake}#{attr}", "--apply", apply])
    if result.returncode != 0:
        raise RuntimeError(f"求值 {attr} 失败：{error_summary(result.stderr)}")
    return json.loads(result.stdout)


def list_hosts(flake: str) -> tuple[dict[str, str | None], dict[str, str]]:
    """返回 (主机 → SSH 别名，本机为 None; 主机 → 配置类别)"""
    aliases = nix_json(flake, "deploy.nodes", "ns: builtins.mapAttrs (n: v: v.hostname) ns")
    kinds = {name: kind for kind in KINDS for name in nix_json(flake, kind, "builtins.attrNames")}
    local = local_profile()
    if local and local not in aliases and local in kinds:
        aliases[local] = None
    return aliases, kinds


def eval_expected(flake: str, kind: str, host: str) -> tuple[str | None, str | None]:
    """返回 (期望的系统路径, 求值错误摘要)"""
    result = run(["nix", "eval", "--raw", f'{flake}#{kind}."{host}".{KINDS[kind]}'])
    if result.returncode != 0:
        return None, error_summary(result.stderr)
    return result.stdout.strip(), None


def probe_host(alias: str | None, timeout: int) -> tuple[tuple | None, str | None]:
    """返回 (解析后的探测结果, 失败原因)；alias 为 None 表示本机，不走 SSH"""
    cmd = ["sh", "-s"]
    if alias is not None:
        cmd = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5", alias, "sh -s"]
    try:
        result = run(cmd, input=PROBE_SCRIPT, timeout=timeout)
    except subprocess.TimeoutExpired:
        return None, f"{timeout} 秒内无响应"
    if result.returncode != 0:
        reason = result.stderr.strip().splitlines()[-1] if result.stderr.strip() else f"退出码 {result.returncode}"
        return None, reason
    try:
        return parse_probe(result.stdout.strip().splitlines()[-1] if result.stdout.strip() else ""), None
    except ValueError as error:
        return None, str(error)


def display_width(text: str) -> int:
    return sum(2 if unicodedata.east_asian_width(c) in "WF" else 1 for c in text)


def format_table(rows: list[tuple[str, ...]]) -> str:
    widths = [max(display_width(row[i]) for row in rows) for i in range(len(HEADER) - 1)]
    lines = []
    for row in rows:
        cells = [cell + " " * (widths[i] - display_width(cell)) for i, cell in enumerate(row[:-1])]
        lines.append("  ".join([*cells, row[-1]]).rstrip())
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("hosts", nargs="*", help="要检查的主机名，默认全部")
    parser.add_argument("--flake", default="", help="直接使用该 flake ref（例如 .），默认固定到 origin/main")
    parser.add_argument("--no-fetch", action="store_true", help="不执行 git fetch")
    parser.add_argument("--jobs", type=int, default=6, help="并发求值的主机数，默认 6")
    parser.add_argument("--timeout", type=int, default=10, help="单台 SSH 探测的总超时秒数，默认 10")
    args = parser.parse_args()

    start = time.monotonic()
    try:
        flake, base = resolve_flake(args)
        aliases, kinds = list_hosts(flake)
    except RuntimeError as error:
        print(error, file=sys.stderr)
        sys.exit(1)
    print(base)

    unknown = [host for host in args.hosts if host not in aliases]
    if unknown:
        print(f"未知主机：{' '.join(unknown)}；可选：{' '.join(sorted(aliases))}", file=sys.stderr)
        sys.exit(2)
    names = sorted(args.hosts or aliases)

    # 求值与探测同时提交，总耗时取决于较慢的一方
    with ThreadPoolExecutor(max_workers=args.jobs) as eval_pool, ThreadPoolExecutor(max_workers=len(names)) as probe_pool:
        evals = {h: eval_pool.submit(eval_expected, flake, kinds[h], h) for h in names}
        probes = {h: probe_pool.submit(probe_host, aliases[h], args.timeout) for h in names}
        results = {h: (*evals[h].result(), *probes[h].result()) for h in names}

    rows = [HEADER]
    counts = dict.fromkeys(STATES, 0)
    for host in names:
        expected, eval_error, probe, probe_error = results[host]
        state = classify(expected, eval_error, probe, probe_error)
        counts[state] += 1
        switched = reboot = "-"
        if probe:
            switched = datetime.fromtimestamp(probe[1]).strftime("%Y-%m-%d %H:%M")
            reboot = REBOOT_TEXT.get(probe[2], "-")
        note = (eval_error or probe_error or "").replace("\n", " ")
        rows.append((host, state, switched, reboot, note[:100]))
    print(format_table(rows))

    summary = "，".join(f"{state} {counts[state]}" for state in STATES)
    print(f"共 {len(names)} 台：{summary}；耗时 {time.monotonic() - start:.0f} 秒")
    sys.exit(0 if counts[UP_TO_DATE] == len(names) else 1)


if __name__ == "__main__":
    main()
