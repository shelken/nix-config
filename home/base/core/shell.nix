{ config, ... }:
let
  shellAliases = {
    urldecode = "python3 -c 'import sys, urllib.parse as ul; print(ul.unquote_plus(sys.stdin.read()))'";
    urlencode = "python3 -c 'import sys, urllib.parse as ul; print(ul.quote_plus(sys.stdin.read()))'";
  };

  localBin = "${config.home.homeDirectory}/.local/bin";
  goBin = "${config.home.homeDirectory}/go/bin";
  rustBin = "${config.home.homeDirectory}/.cargo/bin";
  npmBin = "${config.home.homeDirectory}/.npm-global/bin";
  krewBin = "${config.home.homeDirectory}/.krew/bin";

  envExtra = ''
    export PATH="$PATH:${localBin}:${goBin}:${rustBin}:${npmBin}:${krewBin}"
  '';
in
{
  programs.bash = {
    enable = true;
    enableCompletion = true;
    bashrcExtra = envExtra;
  };
  programs.zsh = {
    enable = true;
    inherit envExtra;
  };

  home.shellAliases = shellAliases;
}
