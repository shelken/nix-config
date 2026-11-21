{ config, ... }:
{
  flake.modules.darwin.desktop.imports = [ config.flake.modules.darwin.iina ];

  flake.modules.darwin.iina = {
    homebrew = {
      brews = [ "ffmpeg" ];
      casks = [ "iina" ];
    };

    system.defaults.CustomUserPreferences."com.colliderli.iina" =
      let
        arrowBtnNextPrev = 1;
      in
      {
        arrowBtnAction = arrowBtnNextPrev;
      };
  };
}
