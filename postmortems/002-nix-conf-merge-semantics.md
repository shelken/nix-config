# Determinate Nix 配置合并导致 custom.conf 修改未生效

**日期**: 2026-07-02
**影响**: 修复 nix-community 缓存时，写入 `nix.custom.conf` 的配置没有形成预期的最终值
**发现人**: shelken

## 问题

修复 001 时，缓存配置明明已经写进 `nix.custom.conf`，Nix 最终看到的值却不一样。原因是 custom.conf 只是中途被 include 的文件，不是最后一层配置。

## 根因

实际读取顺序涉及三处：

1. Determinate 主 `/etc/nix/nix.conf` include `/etc/nix/nix.custom.conf`。
2. 主配置在 include 之后继续写自己的选项。
3. `~/.config/nix/nix.conf` 还能提供用户级配置。

同一个选项被多次设置时，后面的值可能覆盖前面的值，而不是无条件累加（[Nix #9487](https://github.com/NixOS/nix/issues/9487)）。具体表现是：

- custom.conf 若写 `extra-substituters`，会被主配置后写的 `extra-substituters` 覆盖。
- 用户配置若写 `substituters`，会再次覆盖系统缓存列表。

所以问题不是 custom.conf 没生成，而是生成后的值又被后续配置改掉了。

## 修复

当前 `modules/darwin/nix.nix` 采用明确分工：

- `substituters` 写出完整缓存列表，避免与主配置后续的 `extra-substituters` 争用同一追加选项。
- `extra-trusted-public-keys` 只追加 nix-community 公钥，不替换已有公钥。
- 用户级配置不再单独设置 `substituters`。

修改后检查 Nix 的最终值，而不是只检查生成文件：

```bash
nix config show substituters
nix config show trusted-public-keys
```

## 预防

- 修改 Determinate Nix 配置前，先确认主配置的 include 位置、include 后的同名选项和用户级配置。
- 每次修改后都用 `nix config show` 验证最终合并结果，再通过构建确认缓存实际命中。
- `substituters` 与 `extra-substituters`、`trusted-public-keys` 与 `extra-trusted-public-keys` 必须按当前配置层级选择，不能只凭 `extra` 字面含义判断。
