{
  mylib,
  lib,
  config,
  ...
}:
let
  cfg = config.shelken.tools.backup;
in
{
  options.shelken.tools.backup = {
    enable = mylib.mkBoolOpt false "Whether or not use.";
  };
  config = lib.mkIf cfg.enable {
    programs.bash.initExtra = ''
      eval "$(kopia --completion-script-bash)"
    '';
    programs.zsh.initContent = ''
      eval "$(kopia --completion-script-zsh)"
    '';
  };
}
