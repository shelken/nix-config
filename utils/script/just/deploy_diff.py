#!/usr/bin/env python3
"""列出各主机部署当前工作区后会变什么（只求值、只读远端，不构建）。

- 新系统：求值得到系统 drv，它的全部依赖 drv 的输出就是新系统会用到的路径
- 旧系统：远端 /run/current-system 及其依赖图
- 旧闭包里在新系统中不再出现的路径就是变化；只列「自己的依赖都没变」的那些，
  外层的 etc、system-units 等只是被它们连带改变
- 包清单取自 system-path / home-manager-path 两个 buildEnv drv 的 chosenOutputs，新旧都读 drv

主机名单：hosts/default.nix 里带 deploy 的主机，排除 deployDiff = false 的
"""
import argparse
import json
import re
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed

# 求值很吃 CPU，限制同时求值的主机数，不占满机器
EVAL_JOBS = 3
PROBE_TIMEOUT = 15
# 每类最多展示的条目数，其余折叠成「等 N 项」
SHOW = 12

ATTRS = {
    "nixos": 'nixosConfigurations."{}".config.system.build.toplevel.drvPath',
    "darwin": 'darwinConfigurations."{}".system.drvPath',
}
PACKAGE_ENVS = ("system-path", "home-manager-path")

HOSTS_EXPR = """
builtins.mapAttrs (_: h: {
  inherit (h) type;
  deploy = h ? deploy;
  diff = h.deployDiff or true;
}) (import ./hosts)
"""

PROBE = "readlink /run/current-system && nix-store -q --graph /run/current-system"

HASH = re.compile(r"^(/nix/store/)?[0-9a-z]{32}-")
NODE = re.compile(r'^"([^"]+)" \[label')
EDGE = re.compile(r'^"([^"]+)" -> "([^"]+)"')


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def name_of(path):
    """去掉 store 前缀和 hash；双 hash 前缀（flake 源码快照）也一并去掉"""
    name = HASH.sub("", path)
    return HASH.sub("", name)


def split_name(name):
    """git-2.56.0-doc -> (git-doc, 2.56.0)；无版本时版本为空"""
    m = re.match(r"^(.+?)-(\d[^-]*)(-.*)?$", name)
    if not m:
        return name, ""
    return m.group(1) + (m.group(3) or ""), m.group(2)


def error_tail(stderr):
    lines = [l.strip() for l in stderr.splitlines() if l.strip()]
    starts = [i for i, l in enumerate(lines) if l.startswith("error:")]
    return " ".join(lines[starts[-1]:]) if starts else (lines[-1] if lines else "失败")


def list_hosts(only):
    r = run(["nix", "eval", "--impure", "--json", "--expr", HOSTS_EXPR])
    if r.returncode:
        sys.exit(f"读取 hosts/default.nix 失败：{error_tail(r.stderr)}")
    hosts = json.loads(r.stdout)
    picked = {n: h["type"] for n, h in hosts.items() if h["type"] in ATTRS and h["deploy"] and h["diff"]}
    if only:
        unknown = [n for n in only if n not in picked]
        if unknown:
            sys.exit(f"不检查的主机：{' '.join(unknown)}；可选：{' '.join(sorted(picked))}")
        picked = {n: picked[n] for n in only}
    return picked


def probe(host):
    """返回 (当前系统路径, {路径: 它引用的路径集合})"""
    first, _, graph = remote(host, PROBE).partition("\n")
    refs = {}
    for line in graph.splitlines():
        if m := EDGE.match(line):
            # 边 A -> B 表示 B 引用 A
            refs.setdefault(m.group(2), set()).add(m.group(1))
            refs.setdefault(m.group(1), set())
        elif m := NODE.match(line):
            refs.setdefault(m.group(1), set())
    current = first.strip()
    return current, {"/nix/store/" + k: {"/nix/store/" + c for c in v} for k, v in refs.items()}


def store_query(*args):
    r = run(["nix-store", "-q", *args])
    if r.returncode:
        raise RuntimeError(error_tail(r.stderr))
    return r.stdout.split()


def chosen_outputs(shown_json):
    shown = json.loads(shown_json)
    packages = set()
    for d in shown.get("derivations", shown).values():
        for chosen in (d.get("structuredAttrs") or {}).get("chosenOutputs", []):
            packages.update(chosen["paths"])
    return packages


def remote(host, script, timeout=PROBE_TIMEOUT):
    """host 为 None 时在本机执行"""
    cmd = ["sh", "-c", script] if host is None else [
        "ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5", host, script]
    try:
        r = run(cmd, timeout=timeout)
    except subprocess.TimeoutExpired:
        raise RuntimeError(f"{timeout} 秒内无响应")
    if r.returncode:
        raise RuntimeError(error_tail(r.stderr) if r.stderr.strip() else f"退出码 {r.returncode}")
    return r.stdout


def old_packages(host, old_refs):
    """旧系统各包环境的包清单 {环境名: 路径集合，同名合并}，以及旧 drv 已被清理的环境名。
    读旧 buildEnv drv 的 chosenOutputs：被同名文件盖住的包、空包不会出现在引用里，只看引用会误报新增。
    NixOS 远端构建，drv 在远端；darwin 在本机构建，drv 在本机。都没有时退回读引用，只用来判断升级"""
    envs = [p for p in old_refs if name_of(p) in PACKAGE_ENVS]
    if not envs:
        return {}, []
    derivers = remote(host, "nix-store -q --deriver " + " ".join(envs)).split()
    packages, missing = {}, []
    for env, deriver in zip(envs, derivers):
        name = name_of(env)
        for where in (host, None):
            try:
                packages.setdefault(name, set()).update(
                    chosen_outputs(remote(where, "nix derivation show " + deriver))
                )
                break
            except RuntimeError:
                continue
        else:
            packages.setdefault(name, set()).update(old_refs[env])
            missing.append(name)
    return packages, missing


def evaluate(host, kind):
    """返回 (新系统路径, 新系统会用到的全部路径, {包环境名: 包路径集合})"""
    r = run(["nix", "eval", "--raw", ".#" + ATTRS[kind].format(host)])
    if r.returncode:
        raise RuntimeError(error_tail(r.stderr))
    drv = r.stdout.strip()
    requisites = store_query("-R", drv)
    drvs = [p for p in requisites if p.endswith(".drv")]
    # derivation show 不给固定输出 drv 的路径，所以输出路径统一向 nix-store 要
    paths = {p for p in requisites if not p.endswith(".drv")}
    for i in range(0, len(drvs), 2000):
        paths.update(store_query("--outputs", *drvs[i : i + 2000]))
    top = store_query("--outputs", drv)[0]
    envs = [p for p in drvs if name_of(p).removesuffix(".drv") in PACKAGE_ENVS]
    packages = {}
    for env in envs:
        r = run(["nix", "derivation", "show", env])
        if r.returncode:
            raise RuntimeError(error_tail(r.stderr))
        # darwin 的闭包里有不止一个同名的 system-path，同名合并
        packages.setdefault(name_of(env).removesuffix(".drv"), set()).update(chosen_outputs(r.stdout))
    return top, paths, packages


def by_pname(paths):
    groups = {}
    for p in paths:
        pname, version = split_name(name_of(p))
        groups.setdefault(pname, set()).add(version)
    return groups


def fmt_versions(vs):
    return ",".join(sorted(v for v in vs if v)) or "?"


def package_changes(old_packages, new_packages):
    """同一包环境的新旧包清单：先按包名分组再比，同名包换了路径算升级或重建"""
    o, n = by_pname(old_packages), by_pname(new_packages)
    old_paths, new_paths = group_paths(old_packages), group_paths(new_packages)
    upgraded, rebuilt = [], []
    for k in sorted(o.keys() & n.keys()):
        if o[k] != n[k]:
            upgraded.append(f"{k} {fmt_versions(o[k])} → {fmt_versions(n[k])}")
        elif old_paths[k] != new_paths[k]:
            rebuilt.append(k)
    return upgraded, rebuilt, sorted(n.keys() - o.keys()), sorted(o.keys() - n.keys())


def group_paths(paths):
    groups = {}
    for p in paths:
        groups.setdefault(split_name(name_of(p))[0], set()).add(p)
    return groups


# 由包清单派生的聚合目录，包的变化已单独列出
DERIVED = re.compile(r"^(system-path|home-manager-(path|applications|fonts))$")


def source_changes(old_refs, new_paths, package_paths):
    """旧闭包里消失、且自己的依赖都没变的路径：变化的源头"""
    changed = {p for p in old_refs if p not in new_paths}
    leaves = [p for p in changed if not (old_refs[p] & changed)]
    new_only = by_pname(new_paths - set(old_refs))
    lines = set()
    for p in leaves:
        name = name_of(p)
        if p in package_paths or DERIVED.match(name):
            continue
        pname, version = split_name(name)
        target = new_only.get(pname)
        if target and version and version not in target:
            lines.add(f"{pname} {version} → {fmt_versions(target)}")
        else:
            lines.add(name)
    return sorted(lines)


def fold(items):
    if len(items) <= SHOW:
        return "、".join(items)
    return "、".join(items[:SHOW]) + f" 等 {len(items)} 项"


def check(host, kind, probe_future):
    start = time.monotonic()
    top, new_paths, new_packages = evaluate(host, kind)
    current, old_refs = probe_future.result()
    if top == current:
        return "最新", [], time.monotonic() - start
    old_pkgs, missing = old_packages(host, old_refs)
    upgraded, rebuilt, added, removed = set(), set(), set(), set()
    for env in old_pkgs.keys() | new_packages.keys():
        up, rb, add, rm = package_changes(old_pkgs.get(env, set()), new_packages.get(env, set()))
        upgraded.update(up), rebuilt.update(rb)
        # 按引用推算时，被覆盖的包、空包会像新增，传播进来的包会像删除
        if env not in missing:
            added.update(add), removed.update(rm)
    package_paths = set().union(*old_pkgs.values(), *new_packages.values())
    upgraded, added, removed = sorted(upgraded), sorted(added), sorted(removed)
    sources = sorted(rebuilt | set(source_changes(old_refs, new_paths, package_paths)))
    details = []
    for label, items in (("升级", upgraded), ("新增", added), ("删除", removed), ("改动", sources)):
        if items:
            details.append(f"{label}：{fold(items)}")
    if missing:
        details.append(f"（{'、'.join(missing)} 的旧 drv 已被清理，看不出其中新增或删除了哪些包）")
    return "需部署", details, time.monotonic() - start


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("hosts", nargs="*", help="只检查这些主机，默认全部")
    args = parser.parse_args()

    start = time.monotonic()
    hosts = list_hosts(args.hosts)
    total, done, counts = len(hosts), 0, {}
    print(f"检查 {total} 台：{' '.join(sorted(hosts))}", flush=True)

    with ThreadPoolExecutor(max_workers=total) as probe_pool, ThreadPoolExecutor(max_workers=EVAL_JOBS) as eval_pool:
        probes = {h: probe_pool.submit(probe, h) for h in hosts}
        futures = {eval_pool.submit(check, h, k, probes[h]): h for h, k in hosts.items()}
        for future in as_completed(futures):
            host = futures[future]
            done += 1
            try:
                state, details, took = future.result()
                head = f"[{done}/{total}] {host}  {state}  {took:.0f}s"
            except RuntimeError as error:
                state, details = ("不可达" if probes[host].done() and probes[host].exception() else "求值失败"), [str(error)[:200]]
                head = f"[{done}/{total}] {host}  {state}"
            counts[state] = counts.get(state, 0) + 1
            print(head, flush=True)
            for line in details:
                print(f"    {line}", flush=True)

    summary = "，".join(f"{k} {v}" for k, v in counts.items())
    print(f"共 {total} 台：{summary}；耗时 {time.monotonic() - start:.0f} 秒")


if __name__ == "__main__":
    main()
