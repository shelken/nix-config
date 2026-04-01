# Kitty Configuration

## 配置说明

**生效配置**：`default.nix`（通过 home-manager 管理，nix-darwin 构建时生效）

**`kitty.conf`**：仅作为备份/参考，与 `default.nix` 保持内容同步，不会被 kitty 直接加载。

> 修改快捷键或设置时，请以 `default.nix` 为准，同步更新 `kitty.conf` 保持一致。

## Issue

### fix `'xterm-kitty': unknown terminal type` when ssh

try with:

```bash
# it will automatically copy over the terminfo files
kitten ssh <host>
```
