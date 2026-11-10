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

  # 小鹤双拼实际读到的上游文件：方案本身、它声明的两个依赖方案、三者引用的词库与符号表。
  # 其余方案和上游仓库的杂项不进用户目录
  upstreamFiles = [
    "default.yaml"
    "squirrel.yaml"
    "double_pinyin_flypy.schema.yaml"
    "melt_eng.schema.yaml"
    "melt_eng.dict.yaml"
    "radical_pinyin.schema.yaml"
    "radical_pinyin.dict.yaml"
    "rime_ice.dict.yaml"
    "symbols_caps_v.yaml"
  ];
  upstreamDirs = [
    "cn_dicts"
    "en_dicts"
    "lua"
    "opencc"
  ];

  # 上游改名或删文件时在求值阶段报错，而不是部署后输入法静默缺功能
  upstream =
    name:
    assert lib.assertMsg (builtins.pathExists "${inputs.rime-main}/${name}")
      "rime: 上游 rime-ice 缺少 ${name}";
    {
      source = "${inputs.rime-main}/${name}";
      force = true;
    };

  customFiles = {
    "default.custom.yaml" = ./custom/default.custom.yaml;
    "double_pinyin_flypy.custom.yaml" = ./custom/double_pinyin_flypy.custom.yaml;
    "squirrel.custom.yaml" = ./custom/squirrel.custom.yaml;
  };

  # 按内容取指纹：用仓库源路径的话，任何无关提交都会让它变
  sourceStamp = builtins.hashString "sha256" (
    lib.concatStrings (
      [ inputs.rime-main.outPath ]
      ++ upstreamFiles
      ++ upstreamDirs
      ++ map (builtins.hashFile "sha256") (lib.attrValues customFiles)
    )
  );
in
{
  home.file =
    lib.genAttrs' upstreamFiles (name: lib.nameValuePair "${rimeDir}/${name}" (upstream name))
    // lib.genAttrs' upstreamDirs (
      name: lib.nameValuePair "${rimeDir}/${name}" (upstream name // { recursive = true; })
    )
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
