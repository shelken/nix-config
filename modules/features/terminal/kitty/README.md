# Kitty Configuration

## 配置说明

**生效配置**：`_kitty-hm.nix`（配置本体，通过 home-manager 管理；`default.nix` 将该功能挂入 darwin / nixos 的 gui 角色）

**`kitty.conf`**：仅作为备份与参考，与 `_kitty-hm.nix` 保持内容同步，不会被 kitty 直接加载

> 修改快捷键或设置时，以 `_kitty-hm.nix` 为准，同步更新 `kitty.conf` 保持一致

## 常见问题

### SSH 连接远程主机报 `'xterm-kitty': unknown terminal type`

使用 `kitten ssh` 替代原始 ssh，自动向远端同步 terminfo 定义：

```bash
# it will automatically copy over the terminfo files
kitten ssh <host>
```
