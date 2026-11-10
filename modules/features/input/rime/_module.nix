{
  config,
  inputs,
  lib,
  mylib,
  ...
}:
let
  # 鼠须管只在 darwin
  rimeDir = "Library/Rime";
  squirrel = "/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel";

  customFiles = {
    "default.custom.yaml" = ./custom/default.custom.yaml;
    "double_pinyin_flypy.custom.yaml" = ./custom/double_pinyin_flypy.custom.yaml;
    "squirrel.custom.yaml" = ./custom/squirrel.custom.yaml;
  };

  # 按内容取指纹：用仓库源路径的话，任何无关提交都会让它变
  sourceStamp = builtins.hashString "sha256" (
    lib.concatStrings (
      [ inputs.rime-main.outPath ] ++ map (builtins.hashFile "sha256") (lib.attrValues customFiles)
    )
  );
in
{
  home.file = {
    "${rimeDir}" = {
      source = inputs.rime-main;
      recursive = true;
      force = true;
    };
  }
  // lib.mapAttrs' (
    name: path: lib.nameValuePair "${rimeDir}/${name}" (mylib.mkConfigFile config path)
  ) customFiles;

  # Nix store 里的文件 mtime 恒为 1，rime 靠 mtime 判断配置是否变化，
  # 所以源更新后它仍认为 build/ 里编译好的 yaml 是最新的。指纹变了就删掉它们并重新部署
  home.activation.rimeRedeploy = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    rimeBuild="$HOME/${rimeDir}/build"
    if [ "$(cat "$rimeBuild/.nix-source-stamp" 2>/dev/null)" != "${sourceStamp}" ]; then
      run mkdir -p "$rimeBuild"
      run rm -f "$rimeBuild"/*.yaml
      if [[ ! -v DRY_RUN ]]; then
        echo "${sourceStamp}" > "$rimeBuild/.nix-source-stamp"
      fi
      if [ -x "${squirrel}" ]; then
        run "${squirrel}" --reload
      fi
    fi
  '';
}
