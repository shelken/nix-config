# nixos 使用 vscode remote ssh

> [nix-community/nixos-vscode-server](https://github.com/nix-community/nixos-vscode-server)

in `flake.nix`

```nix
vscode-server = {
  url = "github:nix-community/nixos-vscode-server/fc900c16";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

从home-manager引入

```nix
{vscode-server, ...}: let
  vscode-server-home = vscode-server + "/modules/vscode-server/home.nix";
in {
  imports = [
    vscode-server-home
  ];

  services.vscode-server.enable = true;
}
```

`just sw` 更新配置

```shell
# 需要执行命令开启
systemctl --user enable auto-fix-vscode-server.service
systemctl --user start auto-fix-vscode-server.service
```
