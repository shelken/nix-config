"""宿主 icache 开关打开时，把 mise 的下载改写规则带进 VM。

开关在宿主上随时切换，VM 看不到宿主文件；每个上下文、每次 sync 都由 sb 现启动，
所以每次 msb exec 前现读一次，以 MISE_URL_REPLACEMENTS 交给 guest。
"""

from __future__ import annotations

import json
import tomllib

from .config import Config
from .errors import SbError


def exec_env_args(cfg: Config) -> list[str]:
    """开关关闭（文件不存在）时返回空列表，guest 直连原站。"""
    path = cfg.mise_url_replacements_file
    try:
        with open(path, "rb") as f:
            rules = tomllib.load(f)["settings"]["url_replacements"]
    except FileNotFoundError:
        return []
    except (OSError, tomllib.TOMLDecodeError, KeyError) as e:
        raise SbError(f"读不到 mise 下载改写规则（{path}）：{e}") from e
    return ["-e", "MISE_URL_REPLACEMENTS=" + json.dumps(rules, ensure_ascii=False)]
