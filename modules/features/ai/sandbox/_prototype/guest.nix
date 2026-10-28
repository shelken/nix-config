# PROTOTYPE：guest 工具环境、sync/status 和执行上下文隔离器。
# 旧实现作为原型后端复用；下层只接收 spec，不再读取整个 Home Manager config。
{
  pkgs,
  lib,
  nixpkgs,
  spec,
  gitConfig,
}:
let
  generated = import ../_generator.nix {
    inherit
      pkgs
      lib
      nixpkgs
      gitConfig
      ;
    config.shelken.dev = {
      tools = spec.tools;
      miseTools = spec.miseTools;
      sandbox = {
        writableRoots = spec.writableRoots;
        hostCommands = spec.hostCommands;
      };
    };
  };

  launcher = import ../_launcher.nix {
    inherit pkgs gitConfig;
    inherit (generated) linuxPkgs guestBinPath;
  };
in
{
  system = generated.linuxPkgs.stdenv.hostPlatform.system;
  environment = generated.guestBinPath;

  tools = {
    status = generated.guestStatus;
    sync = "/run/sandbox-config/current/sync-guest.sh";
    versions = spec.miseTools;
  };

  contexts = {
    enter = launcher;
    writableRoots = spec.writableRoots;
    owns = [
      "mounts"
      "user namespace"
      "network grants"
      "slot allocation"
      "exit cleanup"
    ];
  };

  publicationSource = generated.publishScript;
}
