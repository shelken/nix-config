# ChatGPT 桌面客户端
{ config, ... }:
{
  flake.modules.darwin.workstation.imports = [ config.flake.modules.darwin.gpt ];

  flake.modules.darwin.gpt.homebrew.casks = [ "chatgpt" ];
}
