{...}: {
  xdg.configFile = {
    "raycast/custom-commands" = {
      source = ./raycast;
      recursive = true;
    };
  };
}
