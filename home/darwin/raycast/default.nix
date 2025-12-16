{
  config,
  lib,
  secrets,
  ...
}:
let
  cfg = config.shelken.secrets;
  rayconfig_path = "${secrets}/raycast/latest.rayconfig";
in
{
  config = lib.mkIf cfg.enable {
    xdg.configFile = {
      "raycast/latest.rayconfig" = {
        source = rayconfig_path;
      };
    };
    # home.activation.RaycastLoginItem = lib.hm.dag.entryAfter [ "writeBoundary" ] (
    #   mylib.mkLoginItemString { app_name = "Raycast"; }
    # );
  };
}
