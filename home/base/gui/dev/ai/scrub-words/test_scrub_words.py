"""scrub-words 端到端测试：用临时目录驱动真实 CLI。运行：python3 test_scrub_words.py"""

import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("scrub_words.py")
DICT = "傻逼 -> 傻瓜\n傻逼玩意->笨东西\n# 注释\n\nfuck  ->  heck\n"


def title_line():
    head = '{"type":"title","v":1,"title":"傻逼玩意 标题","source":"auto","pad":"'
    pad = 255 - len((head + '"}').encode())  # 含换行共 256 字节
    return head + " " * pad + '"}'


def msg(text, **extra):
    return json.dumps({"type": "message", "text": text, **extra}, ensure_ascii=False)


class ScrubWords(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = Path(tmp.name)
        self.root = self.tmp / "sessions"
        self.cache = self.tmp / "cache"
        (self.root / "proj").mkdir(parents=True)
        (self.tmp / "dict.txt").write_text(DICT, encoding="utf-8")
        self.lines = [
            title_line(),
            msg("你真是个傻逼玩意，傻逼"),
            msg("Fuck this, fucking thing\nfuck"),
            r'{"text":"\u50bb\u903c"}',  # JSON 转义形式
            msg("傻逼", thinkingSignature="Ep4xCpsxAWkU"),  # 带真签名，不能改
            msg("没有脏话"),
        ]
        self.old = self.root / "proj" / "old.jsonl"
        self.old.write_bytes(("\n".join(self.lines) + "\n").encode())
        self.before = self.old.read_bytes()
        past = time.time() - 86400
        os.utime(self.old, (past, past))
        self.mtime = self.old.stat().st_mtime_ns
        self.fresh = self.root / "proj" / "fresh.jsonl"
        self.fresh.write_text(msg("傻逼") + "\n", encoding="utf-8")

    def cli(self, *args, ok=True, root=None, cwd=None, stdin=""):
        r = subprocess.run(
            [sys.executable, str(SCRIPT), args[0], "--dict", str(self.tmp / "dict.txt"),
             "--cache", str(self.cache), "--root", str(root or self.root), *args[1:]],
            capture_output=True, text=True, input=stdin, cwd=cwd,
        )
        if ok:
            self.assertEqual(r.returncode, 0, r.stderr)
        return r

    def test_dry_run_changes_nothing(self):
        out = self.cli("dry-run").stdout
        self.assertEqual(self.old.read_bytes(), self.before)
        self.assertIn("傻逼玩意 → 笨东西", out)
        self.assertIn("fresh.jsonl", out)  # 近期写入的文件被列为跳过

    def test_stat_prints_counts_without_paths(self):
        out = self.cli("dry-run", "--stat").stdout
        self.assertIn("傻逼玩意 → 笨东西", out)
        self.assertNotIn("fresh.jsonl", out)
        self.assertNotIn("…", out)

    def test_run_replaces_and_undo_restores(self):
        self.cli("run")
        new = self.old.read_bytes().decode().split("\n")
        self.assertEqual(len((new[0] + "\n").encode()), 256)  # title 行定长
        self.assertIn("笨东西，傻瓜", new[1])  # 长词优先
        self.assertIn("笨东西 标题", new[0])
        self.assertEqual(new[2], msg("heck this, fucking thing\nheck"))  # 大小写不敏感且带词边界
        self.assertEqual(json.loads(new[3])["text"], "傻瓜")  # 转义形式同样替换
        self.assertEqual(new[4], self.lines[4])  # 签名行原样
        self.assertEqual(self.old.stat().st_mtime_ns, self.mtime)  # 不打乱会话排序
        self.assertIn("傻逼", self.fresh.read_text(encoding="utf-8"))  # 活跃文件未动

        self.cli("undo")
        self.assertEqual(self.old.read_bytes(), self.before)
        self.assertFalse(self.cache.exists() and any(self.cache.iterdir()))

    def test_undo_skips_lines_edited_afterwards(self):
        self.cli("run")
        text = self.old.read_text(encoding="utf-8").replace("傻瓜", "改过了", 1)
        self.old.write_text(text, encoding="utf-8")
        out = self.cli("undo", "--min-age", "0").stdout
        self.assertIn("内容已被改动", out)
        self.assertIn("改过了", self.old.read_text(encoding="utf-8"))
        self.assertTrue(any(self.cache.iterdir()))  # 有未恢复的行，日志保留

    def test_purge_all(self):
        self.cli("run")
        self.cli("purge", "--all")
        self.assertFalse(self.cache.exists())

    def test_rejects_value_containing_key(self):
        (self.tmp / "dict.txt").write_text("傻 -> 傻逼\n", encoding="utf-8")
        r = self.cli("dry-run", ok=False)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("连锁替换", r.stderr)

    def test_empty_replacement_deletes_word(self):
        (self.tmp / "dict.txt").write_text("傻逼 ->\n", encoding="utf-8")
        self.cli("run")
        self.assertEqual(json.loads(self.old.read_text(encoding="utf-8").split("\n")[1])["text"], "你真是个玩意，")

    def test_rejects_line_without_arrow(self):
        (self.tmp / "dict.txt").write_text("傻逼 傻瓜\n", encoding="utf-8")
        r = self.cli("dry-run", ok=False)
        self.assertIn("第 1 行", r.stderr)

    def test_escaped_backslash_is_not_a_unicode_escape(self):
        (self.tmp / "dict.txt").write_text("操 -> x\n", encoding="utf-8")
        literal = r'{"text":"\\u64cd"}'  # 正文是字面量 \u64cd，不是“操”；误替换会产出非法 JSON
        self.old.write_bytes(self.old.read_bytes() + literal.encode() + b"\n")
        self.cli("run", "--min-age", "0")
        last = self.old.read_text(encoding="utf-8").split("\n")[-2]
        self.assertEqual(last, literal)

    def test_undo_from_another_directory_uses_absolute_paths(self):
        self.cli("run", root="sessions", cwd=self.tmp)
        self.cli("undo", cwd=self.root)
        self.assertEqual(self.old.read_bytes(), self.before)

    def test_run_refuses_while_cache_is_locked(self):
        import fcntl
        self.cache.parent.mkdir(parents=True, exist_ok=True)
        with open(f"{self.cache}.lock", "w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            r = self.cli("run", ok=False)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("另一个 scrub-words", r.stderr)
        self.assertEqual(self.old.read_bytes(), self.before)

    def test_purge_rejects_out_of_range_number(self):
        self.cli("run")
        r = self.cli("purge", ok=False, stdin="0\n")
        self.assertIn("编号无效", r.stderr)
        self.assertTrue(any(self.cache.iterdir()))


if __name__ == "__main__":
    unittest.main()
