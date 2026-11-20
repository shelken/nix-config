{ config, ... }:
{
  flake.modules.nixos.gui.imports = [ config.flake.modules.nixos.anyrun ];

  flake.modules.homeManager.anyrun =
    {
      inputs,
      config,
      lib,
      myvars,
      pkgs,
      ...
    }:
    let
      anyrunPackages = inputs.anyrun.packages.${pkgs.stdenv.hostPlatform.system};
      palette =
        (lib.importJSON "${config.catppuccin.sources.palette}/palette.json")
        .${myvars.catppuccin.flavor}.colors;
    in
    {
      imports = [
        (
          { modulesPath, ... }:
          {
            # Important! We disable home-manager's module to avoid option
            # definition collisions
            disabledModules = [ "${modulesPath}/programs/anyrun.nix" ];
          }
        )
        inputs.anyrun.homeManagerModules.default
      ];

      programs.anyrun = {
        enable = true;
        # The package should come from the same flake as all the plugins to avoid breakage.
        package = anyrunPackages.anyrun;
        config = {
          x.fraction = 0.5;
          y.fraction = 0.05;
          width.fraction = 0.3;

          hideIcons = false;
          ignoreExclusiveZones = false;
          layer = "overlay";
          hidePluginInfo = false;
          closeOnClick = true;
          showResultsImmediately = true;
          maxEntries = null;

          plugins = with anyrunPackages; [
            applications
            dictionary
            nix-run
            rink
            symbols
            translate
            niri-focus
          ];
        };

        extraConfigFiles = {
          "symbols.ron".source = ./conf/symbols.ron;
          "applications.ron".source = ./conf/applications.ron;
        };
      };

      xdg.configFile."anyrun/style.css".source = pkgs.replaceVars ./conf/style.css {
        inherit (myvars.fontFamilies) cjkMonospace monospace;
        background = palette.surface0.hex;
        foreground = palette.text.hex;
        primary = palette.blue.hex;
        secondary = palette.mauve.hex;
      };
    };
}
