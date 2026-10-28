# PROTOTYPE：整个 sandbox 的唯一装配入口，尚未接入正式模块。
{
  pkgs,
  nixpkgs,
  spec,
  lib ? pkgs.lib,
}:
let
  gitConfig = (pkgs.formats.gitIni { }).generate "sandbox-prototype-git" {
    user = spec.gitUser;
    credential."https://github.com".helper = "!gh auth git-credential";
    url."https://github.com/".insteadOf = "git@github.com:";
  };

  guest = import ./guest.nix {
    inherit
      pkgs
      lib
      nixpkgs
      spec
      gitConfig
      ;
  };

  configBundle = import ./config.nix {
    inherit
      pkgs
      lib
      spec
      guest
      ;
  };

  runtime = import ./runtime.nix {
    inherit
      pkgs
      lib
      spec
      guest
      configBundle
      ;
  };
in
{
  inherit
    spec
    guest
    configBundle
    runtime
    ;
  packages = {
    sb = runtime.cli;
    publish = configBundle.publish;
  };

  homeModule = { lib, ... }: {
    home.packages = [ runtime.cli ];
    home.activation.sandboxPrototypePublish = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${lib.getExe configBundle.publish}
    '';
  };
}
