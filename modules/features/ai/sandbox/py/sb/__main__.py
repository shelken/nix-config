"""用法: python -m sb plan <cwd> <sb.yaml>：把执行计划以紧凑 JSON 打到 stdout，失败时 stderr 报错、退出码 1"""

import sys

from .plan import PlanError, resolve_plan


def main(argv: list[str]) -> int:
    if len(argv) != 3 or argv[0] != "plan":
        print("用法: sb-plan plan <cwd> <sb.yaml>", file=sys.stderr)
        return 2
    try:
        print(resolve_plan(argv[1], argv[2]).to_json())
    except PlanError as e:
        print(f"[-] 错误: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
