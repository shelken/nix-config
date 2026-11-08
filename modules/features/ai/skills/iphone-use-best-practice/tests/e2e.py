#!/usr/bin/env python3
"""iphone 对 Pinky 假手机的端到端测试：隔离的 PINKY_HOME 与 IPHONE_HOME，不碰真机、不碰用户的 Pinky。

用法: tests/e2e.py [iphone 脚本路径]；需要 Pinky 可执行文件（PINKY_BIN 或 /Applications/Pinky.app）
"""
import os
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
IPHONE = sys.argv[1] if len(sys.argv) > 1 else str(HERE.parent / "scripts" / "iphone")
PINKY = os.environ.get("PINKY_BIN") or "/Applications/Pinky.app/Contents/MacOS/Pinky"
FAKE = "fake-iphone-17"


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def main():
    tmp = Path(tempfile.mkdtemp(prefix="iphone-e2e-"))
    port = free_port()
    env = {**os.environ, "PINKY_HOME": str(tmp / "pinky"), "IPHONE_HOME": str(tmp / "iphone"),
           "PINKY_BIN": PINKY, "IPHONE_PINKY_URL": f"http://127.0.0.1:{port}/mcp"}
    daemon = subprocess.Popen([PINKY, "daemon", "--fake", "--http", f"127.0.0.1:{port}"], env=env,
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    failures = []

    def iphone(*args):
        r = subprocess.run([IPHONE, *args], env=env, capture_output=True, text=True, timeout=120)
        return r.returncode, r.stdout + r.stderr

    def check(name, cond, detail=""):
        print(("ok   " if cond else "FAIL ") + name)
        if not cond:
            failures.append(name)
            print(detail)

    try:
        for _ in range(50):
            with socket.socket() as s:
                if s.connect_ex(("127.0.0.1", port)) == 0:
                    break
            time.sleep(0.2)

        rc, out = iphone("snapshot")
        check("没有会话时 snapshot 提示先 up", rc == 1 and "iphone up" in out, out)

        rc, out = iphone("up", "--device", FAKE, "--task", "e2e")
        check("up 连上手机并返回首屏", rc == 0 and "Connected" in out and "Dinely" in out, out)

        rc, out = iphone("snapshot")
        check("另一个进程复用会话读到整屏", rc == 0 and "Dinely" in out, out)

        rc, out = iphone("find", "dinely")
        check("find 命中退出码 0", rc == 0 and "Dinely" in out, out)
        rc, out = iphone("find", "不存在的文字")
        check("find 无命中退出码 1", rc == 1, out)

        rc, out = iphone("tap-text", "Settings")
        check("tap-text 点击成功", rc == 0 and out.startswith("settled"), out)

        rc, out = iphone("scroll", "down")
        check("scroll 成功", rc == 0, out)

        rc, out = iphone("shot")
        path = out.splitlines()[0] if out else ""
        check("shot 写出 JPEG", rc == 0 and Path(path).is_file() and Path(path).read_bytes()[:2] == b"\xff\xd8", out)

        rc, out = iphone("key", "home")
        check("key home 成功", rc == 0, out)

        rc, out = iphone("apps")
        check("apps 列出 App", rc == 0 and "Dinely" in out, out)

        rc, out = iphone("down", "--summary", "e2e done")
        check("down 释放手机并清掉会话", rc == 0 and not (tmp / "iphone" / "session").exists(), out)

        rc, out = iphone("snapshot")
        check("down 之后 snapshot 提示先 up", rc == 1 and "iphone up" in out, out)
    finally:
        subprocess.run([PINKY, "quit"], env=env, capture_output=True)
        daemon.terminate()
        subprocess.run(["rm", "-rf", str(tmp)])
    print("\n" + ("全部通过" if not failures else f"失败 {len(failures)} 项: {failures}"))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
