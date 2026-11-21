{ lib, myvars }:
systemConfigurations:
lib.mapAttrs (
  _: system:
  let
    hm = system.config.home-manager.users.${myvars.username};

    failed = map (x: x.message) (lib.filter (x: !x.assertion) hm.assertions);
    checkedHome =
      if failed != [ ] then
        throw ''
          Failed assertions:
          ${lib.concatStringsSep "\n" (map (x: "- ${x}") failed)}''
      else
        lib.foldr (warning: result: builtins.trace "warning: ${warning}" result) hm hm.warnings;
  in
  {
    config = checkedHome;
    inherit (checkedHome.home) activationPackage;
  }
) systemConfigurations
