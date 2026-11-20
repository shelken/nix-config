from __future__ import annotations

import json
import tomllib

from .config import Config
from .errors import SbError


def exec_env_args(cfg: Config) -> list[str]:
    path = cfg.mise_url_replacements_file
    try:
        with open(path, "rb") as f:
            rules = tomllib.load(f)["settings"]["url_replacements"]
    except FileNotFoundError:
        return []
    except (OSError, tomllib.TOMLDecodeError, KeyError) as e:
        raise SbError(f"读不到 mise 下载改写规则（{path}）：{e}") from e
    return ["-e", "MISE_URL_REPLACEMENTS=" + json.dumps(rules, ensure_ascii=False)]
