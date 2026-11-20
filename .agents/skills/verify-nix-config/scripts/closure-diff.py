#!/usr/bin/env python3
import json, os, re, subprocess, sys

def sh(*a):
    r = subprocess.run(a, capture_output=True, text=True)
    if r.returncode:
        raise RuntimeError(r.stderr.strip().splitlines()[-1] if r.stderr.strip() else "failed")
    return r.stdout

def show(drv):
    j = json.loads(sh("nix", "derivation", "show", "-r", drv))
    return j.get("derivations", j)

def key(p): return re.sub(r"^(/nix/store/)?[a-z0-9]{32}-", "", p)
def nrm(s): return re.sub(r"[a-z0-9]{32}-", "H-", s)

def canon(v, loose):
    if isinstance(v, dict): return {nrm(k): canon(x, loose) for k, x in v.items()}
    if isinstance(v, list):
        l = [canon(x, loose) for x in v]
        return sorted(l, key=lambda x: json.dumps(x, sort_keys=True)) if loose else l
    if isinstance(v, str):
        s = nrm(v)
        return sorted(re.split(r"[\n ]", s)) if loose else s
    return v

def group(d):
    g = {}
    for x, v in d.items(): g.setdefault(key(x), []).append((x, v))
    return g

def firsts(v):
    co = (v.get("structuredAttrs") or {}).get("chosenOutputs")
    if co is None: return None
    seen = []
    for x in co:
        s = nrm(json.dumps(x, sort_keys=True))
        if s not in seen: seen.append(s)
    return seen

def compare(a, b):
    A, B = group(show(a)), group(show(b))
    out = {"added": sorted(set(B) - set(A)), "removed": sorted(set(A) - set(B)),
           "hashOnly": 0, "orderOnly": [], "real": [], "collisions": []}
    for n in A:
        if n not in B or {x for x, _ in A[n]} == {x for x, _ in B[n]}: continue
        enc = lambda vs, loose: sorted(json.dumps(canon(v, loose), sort_keys=True) for _, v in vs)
        if enc(A[n], False) == enc(B[n], False): out["hashOnly"] += 1; continue
        if enc(A[n], True) != enc(B[n], True): out["real"].append(n); continue
        out["orderOnly"].append(n)
        for _, va in A[n]:
            if not (va.get("structuredAttrs") or {}).get("ignoreCollisions"): continue
            fa = firsts(va)
            match = [firsts(vb) for _, vb in B[n] if firsts(vb) and sorted(firsts(vb)) == sorted(fa)]
            if not match or match[0] != fa: out["collisions"].append(n)
    return out

def main():
    before, host = sh("git", "rev-parse", sys.argv[1]).strip(), sys.argv[2]
    after = sys.argv[3] if len(sys.argv) > 3 else "."
    refs = {"before": f"git+file://{os.getcwd()}?rev={before}", "after": after}
    kinds = sh("nix", "eval", "--json", ".#darwinConfigurations", "--apply", "builtins.attrNames")
    cls = "darwinConfigurations" if host in json.loads(kinds) else "nixosConfigurations"
    for kind, attr in [("sys", f"{cls}.{host}.config.system.build.toplevel.drvPath"),
                       ("home", f"homeConfigurations.{host}.activationPackage.drvPath")]:
        try:
            d = {s: sh("nix", "eval", "--raw", f"{r}#{attr}").strip() for s, r in refs.items()}
        except RuntimeError as e:
            print(host, kind, "EVAL ERROR:", e); continue
        print(host, kind, json.dumps(compare(d["before"], d["after"]), ensure_ascii=False))

main()
