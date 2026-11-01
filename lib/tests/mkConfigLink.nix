{ lib, mylib }:
let
  root = mylib.relativeToRoot ".";
  snapshot =
    includeReadme:
    builtins.path {
      path = root;
      name = "mkConfigLink-regression";
      filter =
        path: _:
        let
          relative = lib.removePrefix "${toString root}/" (toString path);
        in
        builtins.elem relative [
          "lib"
          "lib/default.nix"
          "lib/tests"
          "lib/tests/calcUniformSchedule.nix"
        ]
        || (includeReadme && relative == "README.md");
    };
  configSource =
    sourceRoot:
    let
      sourceLib = import (sourceRoot + "/lib") {
        inherit lib;
        secrets = { };
        myvars = { };
      };
    in
    sourceLib.mkConfigLink { shelken.dotfiles.liveEdit = false; } (
      sourceLib.relativeToRoot "lib/tests/calcUniformSchedule.nix"
    );
  withoutReadme = configSource (snapshot false);
  withReadme = configSource (snapshot true);
  manifest = builtins.toJSON { source = withReadme; };
  tests = {
    unrelatedRepoFileDoesNotInvalidateConfig = withoutReadme == withReadme;
    manifestRetainsConfigFile = builtins.elem (toString withReadme) (
      builtins.attrNames (builtins.getContext manifest)
    );
  };
in
{
  inherit tests;
  allPassed = builtins.all (passed: passed) (builtins.attrValues tests);
}
