# 安装

CLI 源码在本机开发树，**不**走 npm/GitHub Release 公开分发。只在首次安装或升级时读本文件。

## 首次安装

```sh
# 默认路径（按实际 clone 位置改）
PM_DIR="${HOME}/Code/active/project-memory"
cd "$PM_DIR"
bun install
```

## 可选：编译并 link 到 PATH

```sh
cd "$PM_DIR"
bun run compile
mkdir -p "${HOME}/.local/bin"
ln -sfn "$PM_DIR/dist/project-memory" "${HOME}/.local/bin/project-memory"
```

## 日常调用二选一

Skill 默认用源码入口，免依赖 PATH：

```sh
# A. 源码（推荐给 Agent）
bun run --cwd "$PM_DIR" pm -- status

# B. 已 link 的二进制
project-memory status
```

改 CLI 逻辑只动 `PM_DIR` 仓库；本 Skill 只保留工作流与分析纪律。
