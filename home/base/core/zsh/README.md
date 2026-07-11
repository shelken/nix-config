## 目录说明

- `functions/` — 存放 zsh 函数脚本，目录已加入 `fpath`，所有函数通过 `autoload` 按需加载
- `p10k/` — Powerlevel10k 主题配置

## 特定配置

在 `$HOME/.specific.zsh` 可以自定义 zsh 的一些配置

## functions 函数列表

### `akv`

查询 `shelken-homelab` Azure Key Vault 中的 secret 值。

**用法：**

```zsh /dev/null/example.zsh#L1-4
akv <secret-name>    # 获取指定 secret 的值（结果直接输出到 stdout）
akv --list | -l      # 列出所有 secret 名称
akv --help | -h      # 显示帮助
```

**Tab 补全：**

输入 `akv ` 后按 `Tab`，会自动从 vault 拉取所有 secret 名称，配合已配置的 `fzf-tab`
插件可通过方向键或模糊搜索选择目标 secret。

补全实现文件：`functions/_akv.zsh` → 编译后为 `_akv`，由 zsh 补全系统自动识别（`#compdef akv`
指令注册）。

### `down_gh_files`

从 GitHub 页面 URL 直接下载文件或目录到当前路径，无需手动拼接 API 地址。

**用法：**

```zsh /dev/null/example.zsh#L1-3
down_gh_files <github-url>
# 文件: https://github.com/owner/repo/blob/branch/path/to/file
# 目录: https://github.com/owner/repo/tree/branch/path/to/dir
```

### `cpa-warm`

按 3 并发批量发送 CPA warm 请求。

**用法：**

```zsh /dev/null/example.zsh#L1-5
cpa-warm [--apiurl <url>] [--model <model>] [--envkey <ENV_VAR_NAME>] [--max <n>] [--input <text>]

# 默认值
# --apiurl https://example.com
# --model  gpt-5.4-mini(off)
# --envkey PI_CPA_API_KEY
```

**说明：**

- `--apiurl` 传 base URL，函数内部会自动补 `/v1/chat/completions`
- `--max` 控制总请求数，默认 `1`
- 固定按 `3` 并发分批发送
- 不传 `--input` 时，每次自动生成 `echo <random_int>`
- 传 `--input` 时，每次会在末尾追加 `random_int`，保证每次 input 不同
- 终端默认只显示运行参数摘要，以及成功/失败统计

### `cpa-eval`

用糖果题测试 CPA 模型回答能力。

**用法：**

```zsh /dev/null/example.zsh#L1-6
cpa-eval [--apiurl <url>] [--model <model>] [--envkey <ENV_VAR_NAME>] [--max <n>]

# 常用
cpa-eval --apiurl http://192.168.69.60:8317 --max 20
```

**说明：**

- `--apiurl` 传 base URL，函数内部会自动补 `/v1/chat/completions`
- 直接使用 `curl` 请求接口，不调用或暴露 `cpa` 命令
- 题目来自 `codex-candy-eval` 的糖果题，回答中出现独立的 `21` 判为正确
- 每条汇总结果后会原样打印该次的完整回答
- `--max` 控制测试次数，默认 `1`；大于 `1` 时会默认并行执行，完成一个输出一个结果

## 补全机制说明

`functions/` 目录已加入 `$fpath`，因此符合 `_<command>` 命名规范的文件会被 zsh 补全系统自动发现。  
新增命令的补全只需在 `functions/` 下创建对应的 `_<command>.zsh` 文件（Nix 会自动去掉 `.zsh`
后缀部署），并在首行写上 `#compdef <command>` 即可。
