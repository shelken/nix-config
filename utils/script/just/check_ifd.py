#!/usr/bin/env python3
"""检查所有主机的求值是否依赖构建（IFD，Import From Derivation）。

并行逐台求值 nixosConfigurations 的 `config.system.build.toplevel.drvPath` 与
darwinConfigurations 的 `system.drvPath`，并禁用 IFD。

- 只有 IFD 被禁用的报错才算失败，并打印触发它的 drv
- 其他求值错误（读私有 secrets 失败、测试主机缺根文件系统的断言等）提示后跳过，
  这类主机的 IFD 无法在当前环境检查
"""
import argparse
import json
import re
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor

IFD_DISABLED = "allow-import-from-derivation' is disabled"
DRV_PATH = re.compile(r"'(/nix/store/[^']+?\.drv)(?:\^[^']*)?'")

# 配置类别 → 每台主机要求值的属性路径
KINDS = {
    "nixosConfigurations": "config.system.build.toplevel.drvPath",
    "darwinConfigurations": "system.drvPath",
}


def nix_eval(args: list[str]) -> subprocess.CompletedProcess:
    cmd = ["nix", "eval", "--option", "allow-import-from-derivation", "false", *args]
    return subprocess.run(cmd, capture_output=True, text=True)


def list_hosts(flake: str) -> list[tuple[str, str]]:
    hosts = []
    for kind in KINDS:
        result = nix_eval(["--json", f"{flake}#{kind}", "--apply", "builtins.attrNames"])
        if result.returncode != 0:
            raise RuntimeError(f"列不出 {kind}：{result.stderr.strip()}")
        hosts += [(kind, name) for name in json.loads(result.stdout)]
    return hosts


def error_summary(stderr: str) -> str:
    """取最后一个 `error:` 起的文字：断言失败时消息在 `error:` 之后的多行里"""
    lines = [line.strip() for line in stderr.strip().splitlines() if line.strip()]
    starts = [i for i, line in enumerate(lines) if line.startswith("error:")]
    return " ".join(lines[starts[-1] :]) if starts else (lines[-1] if lines else "nix eval 失败")


def check_host(flake: str, kind: str, host: str) -> tuple[str, str, str]:
    """返回 (host, 状态, 详情)；状态为 ok、ifd、skip"""
    result = nix_eval(["--raw", f'{flake}#{kind}."{host}".{KINDS[kind]}'])
    if result.returncode == 0:
        return host, "ok", ""
    if IFD_DISABLED in result.stderr:
        drvs = sorted(set(DRV_PATH.findall(result.stderr)))
        return host, "ifd", "\n".join(drvs) or result.stderr.strip().splitlines()[-1]
    return host, "skip", error_summary(result.stderr)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--flake", default=".", help="flake ref，默认 .")
    parser.add_argument("--jobs", type=int, default=6, help="并发求值的主机数，默认 6")
    args = parser.parse_args()

    try:
        hosts = list_hosts(args.flake)
    except RuntimeError as error:
        print(error, file=sys.stderr)
        sys.exit(1)

    start = time.monotonic()
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        results = list(pool.map(lambda item: check_host(args.flake, *item), hosts))

    for host, status, detail in sorted(results):
        if status == "ifd":
            print(f"错误：{host} 求值依赖构建（IFD），触发的 drv：\n{detail}")
        elif status == "skip":
            print(f"警告：{host} 求值失败，已跳过：{detail}")
        else:
            print(f"{host}: 无 IFD")

    counts = {status: sum(1 for _, s, _ in results if s == status) for status in ("ok", "ifd", "skip")}
    print(f"共 {len(results)} 台：{counts['ok']} 台无 IFD，{counts['ifd']} 台有 IFD，{counts['skip']} 台跳过，"
          f"耗时 {time.monotonic() - start:.0f} 秒")
    if counts["ifd"]:
        sys.exit(1)


if __name__ == "__main__":
    main()
