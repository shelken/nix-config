{ myvars, ... }:
let
in
rec {
  home.homeDirectory = "/home/${myvars.username}";

  # environment variables that always set at login
  home.sessionVariables = {
  };
}
