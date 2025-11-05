# lib/tests/runner.nix
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

  # 直接导入并执行测试
  calcUniformScheduleTests = import ./calcUniformSchedule.nix {
    lib = pkgs.lib;
    inherit mylib;
  };
in
{
  inherit calcUniformScheduleTests;

  # 检查所有测试是否通过
  allPassed = calcUniformScheduleTests.allPassed && true;
}
