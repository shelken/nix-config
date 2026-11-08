# just 模块

justfile 的组织约定。配方清单不在这里维护，用下面的命令查看

```bash
just --list
just --list --list-submodules
```

## 布局

- 根 `justfile`：全局设置与高频配方，包括构建、flake、gc、git
- `just/*.just`：低频配方按主题拆成模块，由根 `justfile` 的 `mod` 引入，调用方式统一写 `just <模块>::<配方>`，文档、注释与脚本里都不用空格形式 `just <模块> <配方>`
- `utils/script/just/`：只给 justfile 用的脚本。配方体超过几行就放这里，配方只留一行调用
- 平台专属的模块在 `mod` 上加 `[macos]` 或 `[linux]`，另一个平台上整块隐藏

## 模块文件的写法

- 开头写 `set working-directory := '..'`。模块配方默认在模块文件所在目录执行，这一行让它回到仓库根，相对路径与根 `justfile` 一致
- 配方里用到 `"$@"` 时，模块自己写 `set positional-arguments := true`，设置不会从根继承
- 不能引用根 `justfile` 的变量（如 `profile`），否则整个 just 启动失败。需要主机名时用环境变量 `$PROFILE`，它来自 `.host-profile`，环境变量会继承
- 脚本路径写 `{{ justfile_directory() }}/utils/script/just/<脚本>`，在模块里它仍指向仓库根
- 模块内部互相调用写全名，如 `just anywhere::lima-target-ip`
- 配方说明用 `[doc('一句话')]`。`just --list` 只取紧挨着配方的最后一行注释，多行注释会被截断

## 新增或改名

- 日常流程里常用的放根 `justfile`，低频或某一主题专用的放对应模块，没有合适的就新建 `just/<名>.just` 并在根 `justfile` 加一行 `mod`
- 改配方名或模块名后，搜索文档与脚本里的旧调用

```bash
git grep -n "just <旧名>"
```

## 自动检查

平台属性禁用的模块在本机不会被 just 解析，语法错误或引用根变量要到另一个平台才暴露。所以 pre-commit 的 `just-modules` 钩子对 `justfile` 和每个 `just/*.just` 单独解析，定义见 `flake.nix` 的 `pre-commit-check`。手动检查某个模块

```bash
just --justfile just/<名>.just --summary
```
