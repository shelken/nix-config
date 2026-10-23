# 0003. 共享工具单一声明

日期：2026-10-22

## 状态

已采纳 (Accepted)，尚未实现

## 背景与问题

宿主和 Agent 沙箱都需要同一批开发工具。现状里沙箱在 `wrapper.nix` 写死了一份 Linux 工具清单，配置文件靠 `.omp/agent/`、`.agents/` 前缀过滤，OMP 来自 `llm-agents` input。宿主另有 `home.packages`、mise、别名等多处声明

后果：

- 新增一个两边都要的工具，要改两处
- pi 的配置因为前缀写死，没有进沙箱
- `llm-agents` 锁定独立的 nixpkgs（rev 与仓库 nixpkgs 不同），升级 OMP 要连带下载约 1.1 GiB 的 Linux 闭包
- 沙箱工具无法在宿主 nixpkgs 滚动更新时保持不变

宿主工具集合大于等于沙箱，两边清单不要求相等，也不要求版本严格相同，只要求「都有」。获取现状的方式：

```bash
rg -n 'home.packages|globalConfig.tools|programs\.[a-z-]+\.enable' home/base/gui/dev
```

## 决策

1. **只登记共享工具**。新增 option `shelken.dev.tools.<名字>`，只放宿主和沙箱都需要的工具。宿主独有的工具保持原有写法，不迁移
2. **登记内容**：
   - `package`：nixpkgs 属性名，Nix 工具使用，默认取登记名
   - `mise`：mise 工具规格，与 `package` 二选一
   - `files`：随工具进入沙箱的配置文件
   - `postInstall`：安装后脚本，宿主在激活时运行，沙箱在 `sb sync` 时运行
3. **一个工具在两端使用同一种安装方式**。登记为 mise 的工具，宿主也由 mise 提供
4. **Nix 只提供基础工具和运行时**，共享部分为 `rg`、`fd`、`jq`、`gh`、`node`、`python3`、`uv`。其余共享工具走 mise，由用户显式安装，nixpkgs 滚动更新不涉及它们
5. **第一批 mise 共享工具**为 `omp`、`pi`、`codex`、`claude-code`、`bun`。`programs.bun` 删除
6. **沙箱的 Linux Nix 包取自仓库 `nixpkgs`**，宿主取自 `nixpkgs-darwin`，按同一属性名分别解析。删除 `llm-agents` input
7. **沙箱基础环境不属于共享工具**，由 sandbox 模块管理：`bash`、`coreutils`、`curl`、`git`、`mise`，以及 launcher 使用的 `bubblewrap`、`iproute2`、`iptables`。登记为共享工具会让宿主也安装它们，GNU `coreutils`、Nix 版 `bash` 会覆盖 macOS 自带的同名命令
8. **配置随工具登记**。沙箱不再按路径前缀过滤 `home.file`。`.agents/` 下的 skills 与 `AGENTS.md` 作为「agent 通用」条目登记。沙箱专属改写，例如 `models.yml` 中 `127.0.0.1` 改为宿主地址，保留在 sandbox 模块
9. **`sb sync` 显式补齐 mise 工具和插件**。幂等，只安装缺失项，不升级已有项。主 VM 首次创建时自动运行一次。`sb status` 列出已声明未安装的工具。不进入 `omp-sb`、`sb run` 的启动链
10. **guest 的 mise 配置分两层**：登记生成的只读层，和位于 `/data` 的可写层。Agent 临时 `mise use -g` 的工具记在可写层，所有执行上下文共用
11. **OMP 插件只使用仓库的一份清单**，宿主与沙箱各自安装。沙箱中手装的插件会在下次 `sb sync` 时被清理，与宿主激活行为一致
12. **宿主控制命令在沙箱内明确报错**，例如 `spawn-subagent`、`computer-use`。报错原因写在宿主一侧的声明旁

## 考虑过的替代方案

- **所有工具迁入统一登记表并带 `scope` 字段**：能一眼看全清单，但要迁移约 150 条现有声明，宿主侧改动大。宿主独有工具不需要被沙箱感知
- **从宿主 `home.packages` 按名字推导 Linux 包**：实测不可靠。`ctx7`、`lit` 会匹配到 nixpkgs 中同名但无关的包，`deepwiki`、`sec-run` 匹配不到
- **保留 `llm-agents`**：多维护一份 nixpkgs pin，升级 OMP 仍会触发大闭包下载
- **启动时自动补齐 mise 工具**：某次启动会变慢，且违反 `omp-sb` 只处理自身必要条件的约定
- **一个工具在宿主用 Nix、沙箱用 mise**：同一工具出现两套升级语义

## 影响与代价

- 登记为 mise 的工具在宿主也要 `mise install` 才可用，宿主原本用 Nix 安装的同名工具会迁移到 mise
- `nixfmt`、`deadnix`、`statix` 没有 mise 来源，只能留在宿主 Nix，不进沙箱
- `ctx7`、`deepwiki`、`lit`、`ast-grep`、k8s 工具、LSP 和浏览器类工具本决策不登记，需要时再增加条目
- 沙箱 Nix 部分以基础 CLI 和运行时为主，实测 Linux 闭包解压后基础 CLI 约 642 MiB，运行时额外约 309 MiB，低于现有 llm-agents 版本约 1.1 GiB
- 沙箱基础环境与共享工具的边界需要人工判断，边界由决策 7 的理由给出
