# Azure CLI
{ config, ... }:
{
  flake.modules.darwin.workstation.imports = [ config.flake.modules.darwin.azure-cli ];

  flake.modules.darwin.azure-cli.homebrew.brews = [ "azure-cli" ];
}
