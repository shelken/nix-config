{ mylib, ... }:
let
  inherit (mylib) mkBoolOpt;
in
{
  options.shelken.secrets = {
    enable = mkBoolOpt false "Whether or not this host holds age secrets";
  };
}
