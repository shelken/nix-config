{...}: let
in {
  xdg.configFile = {
    "raycast/latest.rayconfig" = {
      source = ./latest.rayconfig;
    };
  };
}
