{ config, ... }:
{
  flake.modules.darwin.gui.imports = [ config.flake.modules.darwin.quicklook ];

  flake.modules.darwin.quicklook.homebrew.casks = [
    "qlmarkdown"
    "syntax-highlight"
  ];
}
