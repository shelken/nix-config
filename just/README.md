# just 模块

justfile 的组织约定。配方清单不在这里维护，用下面的命令查看

```bash
just --list
just --list --list-submodules
```

## 布局

- 根 `justfile` 放全局设置与高频配方；低频按主题拆到 `just/*.just`，统一写 `just <模块>::<配方>`（不用空格形式）
- 超过几行的配方体放 `utils/script/just/`，配方内只留一行调用

## 模块文件的写法

- 开头写 `set working-directory := '..'`。模块配方默认在模块文件所在目录执行，这一行让它回到仓库根，相对路径与根 `justfile` 一致
- 配方里用到 `"$@"` 时，模块自己写 `set positional-arguments := true`，设置不会从根继承
- 不能引用根 `justfile` 的变量（如 `profile`），否则整个 just 启动失败。需要主机名时用环境变量 `$PROFILE`，它来自 `.host-profile`，环境变量会继承
- 脚本路径写 `{{ justfile_directory() }}/utils/script/just/<脚本>`，在模块里它仍指向仓库根
- 模块内部互相调用写全名，如 `just anywhere::kexec-cache`
- 配方说明用 `[doc('一句话')]`。`just --list` 只取紧挨着配方的最后一行注释，多行注释会被截断

## 变更与检查

- 改配方或模块名后，用 `git grep -n "just <旧名>"` 清理文档与脚本中的旧调用
- 平台属性禁用的模块不会在本机被解析，由 pre-commit 的 `just-modules` 钩子逐一校验（见 `.pre-commit-config.yaml`）；手动检查单模块执行 `just --justfile just/<名>.just --summary`
