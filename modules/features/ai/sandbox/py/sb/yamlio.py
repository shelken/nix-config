"""YAML 读取与类型检查。

YAML 一律经 yq：批准哈希（sb trust）用的也是 yq，换解析器会让 YAML 1.1 与 1.2 的差异
（yes/no、八进制、冒号分隔的整数）悄悄改变授权内容。
"""

from __future__ import annotations

import json
import subprocess
from typing import Any

from .errors import SbError


def _yq(path: str, *expr: str) -> bytes:
    r = subprocess.run(["yq", "-o=json", *expr, path], capture_output=True)
    if r.returncode != 0:
        raise SbError(f"无法解析 {path}: {r.stderr.decode().strip()}")
    return r.stdout


def load_mapping(path: str) -> dict[str, Any]:
    """空文件当作空映射；顶层不是映射就报错。"""
    return mapping(json.loads(_yq(path, ".")), path)


def canonical_json(path: str) -> bytes:
    """键排序、无缩进的 JSON，注释与排版变化不影响它。它的 sha256 就是批准哈希，参数一变历史批准记录全部失效。"""
    return _yq(path, "-I=0", "sort_keys(..)")


def mapping(value: Any, where: str) -> dict[str, Any]:
    if value is None:
        return {}
    if not isinstance(value, dict):
        raise SbError(f"{where} 必须是映射，当前是 {type(value).__name__}")
    return value


def as_list(value: Any, where: str) -> list[Any]:
    if value is None:
        return []
    if not isinstance(value, list):
        raise SbError(f"{where} 必须是列表，当前是 {type(value).__name__}")
    return value


def str_list(value: Any, where: str) -> list[str]:
    items = as_list(value, where)
    for item in items:
        if not isinstance(item, str) or not item:
            raise SbError(f"{where} 的每一项必须是非空字符串: {json.dumps(item, ensure_ascii=False)}")
    return items
