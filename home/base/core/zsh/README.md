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

---

### `down_gh_files`

从 GitHub 页面 URL 直接下载文件或目录到当前路径，无需手动拼接 API 地址。

**用法：**

```zsh /dev/null/example.zsh#L1-3
down_gh_files <github-url>
# 文件: https://github.com/owner/repo/blob/branch/path/to/file
# 目录: https://github.com/owner/repo/tree/branch/path/to/dir
```

## 补全机制说明

`functions/` 目录已加入 `$fpath`，因此符合 `_<command>` 命名规范的文件会被 zsh 补全系统自动发现。  
新增命令的补全只需在 `functions/` 下创建对应的 `_<command>.zsh` 文件（Nix 会自动去掉 `.zsh`
后缀部署），并在首行写上 `#compdef <command>` 即可。
