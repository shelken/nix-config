class SbError(Exception):
    """用户可处理的失败。str(e) 是 `[-] 错误:` 之后的完整正文。"""
