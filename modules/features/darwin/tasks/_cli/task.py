# task CLI：声明式定时任务的查看与调试入口
# 标签前缀是占位符，构建时由 lib/tasks.nix 的 labelPrefix 注入，避免两处硬编码漂移
import argparse
import glob
import gzip
import os
import plistlib
import re
import shutil
import subprocess
import sys
import time
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime

LABEL_PREFIX = "@labelPrefix@"
USER_AGENT_DIR = os.path.expanduser("~/Library/LaunchAgents")
ROOT_DAEMON_DIR = "/Library/LaunchDaemons"
TIER_DIRS = (("user", USER_AGENT_DIR), ("root", ROOT_DAEMON_DIR))
WEEKDAYS = ("Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat")

STARTED = re.compile(
    r"^\[(?P<ts>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] ===== Task '(?P<name>[^']+)' "
    r"Started(?: \((?P<trigger>\w+)\))? =====$"
)
FINISHED = re.compile(
    r"^\[(?P<ts>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] ===== Task '(?P<name>[^']+)' "
    r"Finished \(exit code: (?P<code>\d+)\) =====$"
)
JITTER = re.compile(r"^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] Jitter delay: \d+s$")

GREEN = "\x1b[32m"
RED = "\x1b[31m"
YELLOW = "\x1b[33m"
RESET = "\x1b[0m"

HELP = """task —— 声明式定时任务的查看与调试入口

用法:
  task [ls]              任务状态表（上次运行、结果、是否已装载）
  task log <名>          最近一次运行的日志；-n N 最近 N 次，-f 跟随，--all 全部
  task run <名> [参数]   前台执行，输出同时写入日志
  task info <名>         调度、日志与 plist 路径、launchd 状态
  task help -v           完整说明

全局选项:
  --debug                输出各阶段耗时"""

HELP_VERBOSE = HELP + """

任务与日志:
  task 运行时读取已安装的 space.ooooo.task-* launchd plist，只列出真正部署的任务。
  用户任务日志在 ~/Library/Logs/task-<名>.log，root 任务在 /Library/Logs/task-<名>.log。
  每次运行以 "===== Task '<名>' Started (launchd|manual) =====" 开始、
  "===== Task '<名>' Finished (exit code: N) =====" 结束；旧日志没有括号里的触发来源。
  SHELKEN_TASK_LAUNCHD=1 由 launchd 注入，任务据此区分调度唤起与手动运行。

补充:
  task ls --names        每行一个任务名（供 shell 补全使用）
  NO_COLOR=1             关闭 ✓/✗/running 的 ANSI 着色；管道输出本身无色"""


@dataclass
class Task:
    name: str
    tier: str
    plist_path: str
    schedule: str
    log_path: str


@dataclass
class Run:
    start: str
    finished: object
    code: object
    trigger: object
    lines_start_index: int


@dataclass
class Status:
    loaded: bool
    running: bool = False
    runs: object = None
    last_exit: object = None


class Debug:
    def __init__(self, enabled):
        self.enabled = enabled

    @contextmanager
    def phase(self, label, count=None):
        if not self.enabled:
            yield
            return
        started = time.perf_counter()
        try:
            yield
        finally:
            elapsed = (time.perf_counter() - started) * 1000
            name = label if count is None else f"{label} x{count}"
            print(f"debug: {name} {elapsed:.1f}ms", file=sys.stderr)


def default_log_path(name, tier):
    if tier == "root":
        return f"/Library/Logs/task-{name}.log"
    return os.path.expanduser(f"~/Library/Logs/task-{name}.log")


def format_interval(seconds):
    if seconds % 3600 == 0:
        return f"{seconds // 3600}h"
    if seconds > 3600:
        hours, minutes = divmod(seconds, 3600)
        return f"{hours}h{minutes // 60}m" if minutes else f"{hours}h"
    if seconds % 60 == 0:
        return f"{seconds // 60}m"
    return f"{seconds}s"


def format_schedule(plist):
    if "StartInterval" in plist:
        return f"every {format_interval(int(plist['StartInterval']))}"
    if "StartCalendarInterval" in plist:
        intervals = plist["StartCalendarInterval"]
        if isinstance(intervals, dict):
            intervals = [intervals]
        times = []
        for item in intervals:
            clock = f"{item.get('Hour', 0):02d}:{item.get('Minute', 0):02d}"
            if "Weekday" in item:
                clock = f"{WEEKDAYS[item['Weekday'] % 7]} {clock}"
            times.append(clock)
        return ", ".join(times)
    return "manual"


def parse_runs(text):
    runs = []
    current = None
    jitter_at = None
    for index, line in enumerate(text.splitlines()):
        if JITTER.match(line):
            jitter_at = index
            continue
        match = STARTED.match(line)
        if match:
            if current is not None:
                runs.append(current)
            current = Run(
                start=match.group("ts"),
                finished=None,
                code=None,
                trigger=match.group("trigger"),
                lines_start_index=jitter_at if jitter_at == index - 1 else index,
            )
            jitter_at = None
            continue
        match = FINISHED.match(line)
        if match and current is not None:
            current.finished = match.group("ts")
            current.code = int(match.group("code"))
    if current is not None:
        runs.append(current)
    return runs


def select_runs(lines, n):
    runs = parse_runs("\n".join(lines))
    if not runs:
        return []
    first = max(0, len(runs) - n) if n > 0 else 0
    selected = []
    for index in range(first, len(runs)):
        start = runs[index].lines_start_index
        end = runs[index + 1].lines_start_index if index + 1 < len(runs) else len(lines)
        selected.extend(lines[start:end])
    return selected


def select_log_lines(lines, count, all_lines):
    if all_lines:
        return lines
    selected = select_runs(lines, count)
    # 没有任何 Started 标记（纯手动 task-<名> 的残留、格式异常）时回退到末尾若干行，避免打印空
    return selected if selected else lines[-50:]


def colorize(text, enabled):
    if not enabled:
        return text
    if text.startswith("✓"):
        return f"{GREEN}{text}{RESET}"
    if text.startswith("✗"):
        return f"{RED}{text}{RESET}"
    if text.startswith("running"):
        return f"{YELLOW}{text}{RESET}"
    return text


def render_table(rows, color):
    headers = ["NAME", "TIER", "SCHEDULE", "LAST RUN", "RESULT", "LOADED"]
    keys = ["name", "tier", "schedule", "last_run", "result", "loaded"]
    cells = [[str(row.get(key, "")) for key in keys] for row in rows]
    widths = [len(header) for header in headers]
    for row in cells:
        for index, cell in enumerate(row):
            widths[index] = max(widths[index], len(cell))
    lines = ["  ".join(header.ljust(widths[index]) for index, header in enumerate(headers))]
    for row in cells:
        rendered = []
        for index, cell in enumerate(row):
            padding = " " * (widths[index] - len(cell))
            if keys[index] in ("result", "loaded"):
                # 先按纯文本算好宽度再上色，否则 ANSI 转义码会被算进列宽
                rendered.append(colorize(cell, color) + padding)
            else:
                rendered.append(cell + padding)
        lines.append("  ".join(rendered).rstrip())
    return "\n".join(lines)


def read_file(path):
    try:
        with open(path, "rb") as handle:
            return handle.read().decode("utf-8", "replace")
    except OSError:
        return ""


def read_log_text(path):
    # 轮转刚发生时当前日志为空，回看最近一份 gzip 旧档；读全文件是因为单次运行输出可能很长
    # （轮转后单个日志不超过约 1MB）
    text = read_file(path)
    if parse_runs(text):
        return text
    rotated = f"{path}.0.gz"
    if os.path.isfile(rotated):
        try:
            with gzip.open(rotated, "rb") as handle:
                return handle.read().decode("utf-8", "replace")
        except OSError:
            pass
    return text


def latest_run(path):
    runs = parse_runs(read_log_text(path))
    return runs[-1] if runs else None


def count_rotated(path):
    return len(glob.glob(f"{path}.*.gz"))


def load_tasks():
    tasks = {}
    for tier, directory in TIER_DIRS:
        for path in sorted(glob.glob(os.path.join(directory, f"{LABEL_PREFIX}*.plist"))):
            try:
                with open(path, "rb") as handle:
                    plist = plistlib.load(handle)
            except (OSError, plistlib.InvalidFileException, ValueError):
                continue
            label = plist.get("Label", "")
            if not label.startswith(LABEL_PREFIX):
                continue
            name = label[len(LABEL_PREFIX):]
            tasks[name] = Task(
                name=name,
                tier=tier,
                plist_path=path,
                schedule=format_schedule(plist),
                log_path=plist.get("StandardOutPath") or default_log_path(name, tier),
            )
    return tasks


def launchd_status(task):
    domain = "system" if task.tier == "root" else f"user/{os.getuid()}"
    target = f"{domain}/{LABEL_PREFIX}{task.name}"
    try:
        result = subprocess.run(
            ["launchctl", "print", target],
            capture_output=True,
            text=True,
            timeout=10,
        )
    except (OSError, subprocess.SubprocessError):
        return Status(loaded=False)
    if result.returncode != 0:
        return Status(loaded=False)
    output = result.stdout
    running = bool(re.search(r"^\s*state = running$", output, re.M))
    runs = re.search(r"^\s*runs = (\d+)$", output, re.M)
    last_exit = re.search(r"^\s*last exit code = (\d+)$", output, re.M)
    return Status(
        loaded=True,
        running=running,
        runs=int(runs.group(1)) if runs else None,
        last_exit=int(last_exit.group(1)) if last_exit else None,
    )


def fmt_time(timestamp):
    return timestamp[5:16] if timestamp else "-"


def format_duration(seconds):
    if seconds >= 3600:
        hours, rest = divmod(seconds, 3600)
        minutes = rest // 60
        return f"{hours}h{minutes}m" if minutes else f"{hours}h"
    if seconds >= 60:
        minutes, rest = divmod(seconds, 60)
        return f"{minutes}m{rest}s"
    return f"{seconds}s"


def seconds_between(start, finish):
    pattern = "%Y-%m-%d %H:%M:%S"
    delta = datetime.strptime(finish, pattern) - datetime.strptime(start, pattern)
    return int(delta.total_seconds())


def human_size(size):
    if size < 1024:
        return f"{size} B"
    if size < 1024 * 1024:
        return f"{size // 1024} KB"
    return f"{size / (1024 * 1024):.1f} MB"


def result_for(run, status):
    if run is None:
        return "-"
    if run.finished is not None:
        return "✓" if run.code == 0 else f"✗ {run.code}"
    return "running" if status.running else "✗ ?"


def cmd_ls(tasks, names_only, debug):
    if names_only:
        for name in sorted(tasks):
            print(name)
        return 0
    with debug.phase("launchctl", count=len(tasks)):
        statuses = {name: launchd_status(task) for name, task in tasks.items()}
    with debug.phase("parse logs"):
        rows = []
        for name in sorted(tasks):
            task = tasks[name]
            status = statuses[name]
            run = latest_run(task.log_path)
            rows.append(
                {
                    "name": name,
                    "tier": task.tier,
                    "schedule": task.schedule,
                    "last_run": fmt_time(run.start) if run else "-",
                    "result": result_for(run, status),
                    "loaded": "✓" if status.loaded else "✗",
                }
            )
    color = sys.stdout.isatty() and "NO_COLOR" not in os.environ
    print(render_table(rows, color))
    return 0


def resolve_log_path(tasks, name):
    task = tasks.get(name)
    if task is not None:
        return task.log_path
    for tier in ("user", "root"):
        candidate = default_log_path(name, tier)
        if os.path.isfile(candidate):
            return candidate
    return default_log_path(name, "user")


def cmd_log(tasks, name, count, follow, all_lines):
    if not name:
        print("task: 需要任务名\n用法: task log <名>", file=sys.stderr)
        return 1
    path = resolve_log_path(tasks, name)
    if not os.path.isfile(path):
        print(f"task: '{name}' 尚未运行过（无日志文件 {path}）", file=sys.stderr)
        return 1
    if follow:
        os.execvp("tail", ["tail", "-n", "50", "-f", path])
    lines = read_file(path).splitlines()
    print("\n".join(select_log_lines(lines, count, all_lines)))
    return 0


def cmd_run(tasks, name, args):
    if not name:
        print("task: 需要任务名\n用法: task run <名> [参数]", file=sys.stderr)
        return 1
    task = tasks.get(name)
    command = shutil.which(f"task-{name}")
    if command is None and task is None:
        print(f"task: 未知任务 '{name}'", file=sys.stderr)
        return 1
    if task is not None and task.tier == "root" and os.geteuid() != 0:
        os.execvp("sudo", ["sudo", os.path.abspath(sys.argv[0]), "run", name, *args])
    if command is None:
        print(f"task: 找不到 task-{name} 命令", file=sys.stderr)
        return 1
    log_path = task.log_path if task is not None else default_log_path(name, "user")
    os.makedirs(os.path.dirname(log_path), exist_ok=True)
    with open(log_path, "ab") as log_file:
        process = subprocess.Popen([command, *args], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        try:
            for chunk in iter(lambda: process.stdout.read(4096), b""):
                sys.stdout.buffer.write(chunk)
                sys.stdout.buffer.flush()
                log_file.write(chunk)
                log_file.flush()
        except KeyboardInterrupt:
            # 子进程与 CLI 同进程组，SIGINT 已一并送达；等它收尾后返回其退出码，
            # 否则 Python 会打印 traceback
            process.wait()
            return process.returncode if process.returncode is not None else 130
    # 读到 EOF 不会设置 returncode，必须 wait() 才会拿到子进程退出码，否则永远返回 None
    return process.wait()


def log_display(path):
    try:
        size = human_size(os.path.getsize(path))
    except OSError:
        size = "不存在"
    parts = [size]
    rotated = count_rotated(path)
    if rotated:
        parts.append(f"{rotated} rotated")
    return f"{path} ({', '.join(parts)})"


def cmd_info(tasks, name, debug):
    task = tasks.get(name)
    if task is None:
        print(f"task: 未知任务 '{name}'", file=sys.stderr)
        return 1
    with debug.phase("launchctl", count=1):
        status = launchd_status(task)
    with debug.phase("parse logs"):
        run = latest_run(task.log_path)
    print(f"name        {task.name}")
    print(f"tier        {task.tier}")
    print(f"schedule    {task.schedule}")
    print(f"log         {log_display(task.log_path)}")
    print(f"plist       {task.plist_path}")
    if status.loaded:
        state = "running" if status.running else "not running"
        print(f"launchd     loaded, {state}, runs={status.runs}, last exit code={status.last_exit}")
    else:
        print("launchd     not loaded")
    if run is None:
        print("last run    -")
    else:
        suffix = ""
        if run.finished is not None:
            suffix = f" ({format_duration(seconds_between(run.start, run.finished))})"
        print(f"last run    {fmt_time(run.start)} → {result_for(run, status)}{suffix}")
    return 0


def build_parser():
    parser = argparse.ArgumentParser(prog="task", add_help=False)
    subparsers = parser.add_subparsers(dest="command")

    parser_ls = subparsers.add_parser("ls", add_help=False)
    parser_ls.add_argument("--names", action="store_true")

    parser_log = subparsers.add_parser("log", add_help=False)
    parser_log.add_argument("name", nargs="?")
    parser_log.add_argument("-n", dest="count", type=int, default=1, metavar="N")
    parser_log.add_argument("-f", "--follow", action="store_true")
    parser_log.add_argument("--all", dest="all_lines", action="store_true")

    parser_run = subparsers.add_parser("run", add_help=False)
    parser_run.add_argument("name", nargs="?")
    parser_run.add_argument("args", nargs=argparse.REMAINDER)

    parser_info = subparsers.add_parser("info", add_help=False)
    parser_info.add_argument("name")

    return parser


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    debug = Debug("--debug" in argv)
    argv = [arg for arg in argv if arg != "--debug"]
    if not argv:
        argv = ["ls"]

    if argv[0] in ("help", "-h", "--help"):
        verbose = any(arg in ("-v", "--verbose") for arg in argv[1:])
        print(HELP_VERBOSE if verbose else HELP)
        return 0

    args = build_parser().parse_args(argv)
    with debug.phase("scan plists"):
        tasks = load_tasks()

    if args.command == "ls":
        return cmd_ls(tasks, args.names, debug)
    if args.command == "log":
        return cmd_log(tasks, args.name, args.count, args.follow, args.all_lines)
    if args.command == "run":
        return cmd_run(tasks, args.name, args.args)
    if args.command == "info":
        return cmd_info(tasks, args.name, debug)
    print(f"task: 未知命令 '{argv[0]}'\n{HELP}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
