# skill 登记表的接口挂到 core（ADR 0004「接口放 core」）
{ config, ... }:
{
  flake.modules.darwin.core.imports = [ config.flake.modules.darwin.skill-options ];
  flake.modules.nixos.core.imports = [ config.flake.modules.nixos.skill-options ];

  flake.modules.homeManager.skill-options = import ./_skill-options.nix;
}
