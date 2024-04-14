{myvars, ...}: {
  programs.ssh = {
    inherit (myvars.networking.ssh) extraConfig;
  };
}
