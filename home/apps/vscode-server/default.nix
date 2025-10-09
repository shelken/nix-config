{ vscode-server, ... }:
let
  vscode-server-home = vscode-server + "/modules/vscode-server/home.nix";
in
{
  imports = [
    vscode-server-home
  ];

  services.vscode-server.enable = true;
}
