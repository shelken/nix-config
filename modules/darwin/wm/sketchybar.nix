{pkgs, ...}: let
  logFile = "/var/tmp/sketchybar.log";
in {
  services.sketchybar = {
    enable = true;
    # extraPackages = with pkgs; [
    #   (callPackage ../../../home/darwin/wm/sketchyhelper.nix { })
    # ];
    # extraPackages = with pkgs; [
    #   coreutils
    #   curl
    #   # gh
    #   gnugrep
    #   gnused
    #   jq
    #   lua5_4
    #   # wttrbar
    #   # (callPackage ../../../home/darwin/wm/sketchyhelper.nix { })
    # ];
  };

  launchd.user.agents.sketchybar = {
    serviceConfig.StandardErrorPath = logFile;
    serviceConfig.StandardOutPath = logFile;
  };

  # environment.systemPackages = [
  #   (pkgs.callPackage ../../../home/darwin/wm/sketchyhelper.nix { })
  # ];
}
