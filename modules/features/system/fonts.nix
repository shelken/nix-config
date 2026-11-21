{ config, ... }:
let
  iosevkaMono =
    pkgs:
    pkgs.runCommand "nerd-fonts-iosevka-mono-${pkgs.nerd-fonts.iosevka.version}"
      {
        preferLocalBuild = true;
        allowSubstitutes = false;
      }
      ''
        dir=share/fonts/truetype/NerdFonts/Iosevka
        mkdir -p $out/$dir
        cp ${pkgs.nerd-fonts.iosevka}/$dir/IosevkaNerdFontMono-* $out/$dir/
      '';

  packages =
    pkgs: with pkgs; [
      material-design-icons
      font-awesome

      source-sans
      source-serif

      nerd-fonts.symbols-only
      (iosevkaMono pkgs)

      maple-mono.NF-CN-unhinted
    ];
in
{
  flake.modules.darwin.desktop.imports = [ config.flake.modules.darwin.fonts ];
  flake.modules.nixos.gui.imports = [ config.flake.modules.nixos.fonts ];

  flake.modules.darwin.fonts =
    { pkgs, ... }:
    {
      fonts.packages = packages pkgs;
    };

  flake.modules.nixos.fonts =
    { pkgs, ... }:
    {
      fonts.packages = packages pkgs;
    };

  flake.modules.homeManager.fonts =
    { myvars, ... }:
    {
      fonts.fontconfig = {
        enable = true;
        defaultFonts.monospace = [
          myvars.fontFamilies.monospace
          myvars.fontFamilies.cjkMonospace
        ];
      };
    };
}
