# AI 工具链的同步任务，由根 justfile 以 `mod ai` 引入：just ai <配方>

# 同步 magpie 模型能力差集到 omp models.yml
mp-sync:
    @{{ justfile_directory() }}/utils/script/just/sync-mp-models.sh

# 按模型上下文窗口回填 pi settings.json 的 reserveTokens（节点见脚本开头）
pi-compaction:
    @{{ justfile_directory() }}/utils/script/just/sync_pi_compaction.py
