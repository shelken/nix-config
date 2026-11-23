{ config, ... }:
{
  flake.modules.darwin.homelab.imports = [ config.flake.modules.darwin.lm-studio ];

  flake.modules.darwin.lm-studio.homebrew.casks = [ "lm-studio" ];

  flake.modules.homeManager.lm-studio =
    {
      lib,
      config,
      ...
    }:
    let
      pathExtra = ''export PATH="$PATH:$HOME/.lmstudio/bin"'';
    in
    {
      programs.zsh.envExtra = lib.mkIf config.programs.zsh.enable pathExtra;
      programs.bash.bashrcExtra = lib.mkIf config.programs.bash.enable pathExtra;
    };
}
