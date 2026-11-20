let
  pkgs = import <nixpkgs> { };
  secrets = { };
  myvars = {
    username = "testuser";
  };

  mylib = import ../default.nix {
    lib = pkgs.lib;
    inherit secrets myvars;
  };

  calcUniformScheduleTests = import ./calcUniformSchedule.nix {
    lib = pkgs.lib;
    inherit mylib;
  };
in
{
  inherit calcUniformScheduleTests;

  allPassed = calcUniformScheduleTests.allPassed && true;
}
