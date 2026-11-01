{ lib, mylib }:
let
  root = mylib.relativeToRoot ".";
  skillDir = "modules/features/ai/skills/subagent-policy";
  # 最小仓库副本：lib、一个读取兄弟文件的脚本目录，可选 README
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
        relative == "lib"
        || lib.hasPrefix "lib/" relative
        || builtins.elem relative [
          "modules"
          "modules/features"
          "modules/features/ai"
          "modules/features/ai/skills"
          skillDir
          "${skillDir}/spawn-subagent"
          "${skillDir}/subagent-config.json"
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
      sourceLib.relativeToRoot "${skillDir}/spawn-subagent"
    );
  withoutReadme = configSource (snapshot false);
  withReadme = configSource (snapshot true);
  manifest = builtins.toJSON { source = withReadme; };
  tests = {
    unrelatedRepoFileDoesNotInvalidateConfig = withoutReadme == withReadme;
    keepsRepoRelativeLayout = lib.hasSuffix "/${skillDir}/spawn-subagent" withReadme;
    keepsSiblingFiles = builtins.pathExists "${dirOf withReadme}/subagent-config.json";
    manifestRetainsConfigSource = builtins.any (p: lib.hasPrefix p withReadme) (
      builtins.attrNames (builtins.getContext manifest)
    );
  };
in
{
  inherit tests;
  allPassed = builtins.all (passed: passed) (builtins.attrValues tests);
}
