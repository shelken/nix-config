{pkgs, ...}: {
  imports = [
    ../base.nix
    ./base
    ./docker.nix
  ];

  environment.systemPackages = with pkgs; [
    # create a fhs environment by command `fhs`, so we can run non-nixos packages in nixos! TODO?
    (
      let
        base = pkgs.appimageTools.defaultFhsEnvArgs;
      in
        pkgs.buildFHSUserEnv (base
          // {
            name = "fhs";
            targetPkgs = pkgs: (base.targetPkgs pkgs) ++ [pkgs.pkg-config];
            profile = "export FHS=1";
            runScript = "bash";
            extraOutputsToInstall = ["dev"];
          })
    )
  ];

  services.qemuGuest.enable = true; # qemu-guest-agent
  systemd.services."serial-getty@ttyS0".enable = true;
}
