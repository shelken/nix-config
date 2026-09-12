{ lib, ... }:
{
  options.shelken.internal.homeModules = lib.mkOption {
    type = lib.types.listOf lib.types.deferredModule;
    default = [ ];
    internal = true;
    description = "由系统功能拥有的 Home Manager 模块。";
  };
}
