{
  config,
  inputs,
  lib,
  mylib,
  myvars,
  ...
}:
let
  # 鼠须管只在 darwin
  rimeDir = "Library/Rime";
  squirrel = "/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel";
  # 各设备共用的同步目录，靠 iCloud「桌面与文稿」在设备间传递
  syncDir = "${config.home.homeDirectory}/Documents/rime/sync";

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

  squirrelTheme = import ./_squirrel-theme.nix { inherit config lib myvars; };

  # 按内容取指纹：用仓库源路径的话，任何无关提交都会让它变
  sourceStamp = builtins.hashString "sha256" (
    lib.concatStrings (
      [ inputs.rime-main.outPath ]
      ++ upstreamFiles
      ++ upstreamDirs
      ++ [ squirrelTheme ]
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
    ) customFiles
    // {
      "${rimeDir}/squirrel_catppuccin.yaml" = {
        text = squirrelTheme;
        force = true;
      };
    };

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

  # installation.yaml 由 rime 自己读写，不能整份接管：只在缺 sync_dir 时补上。
  # 没有它 rime 会同步到本机的 ~/Library/Rime/sync，设备之间互相看不到
  home.activation.rimeSyncDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    rimeInstallation="$HOME/${rimeDir}/installation.yaml"
    if [ -f "$rimeInstallation" ] && ! /usr/bin/grep -q '^sync_dir:' "$rimeInstallation"; then
      if [[ ! -v DRY_RUN ]]; then
        printf '\nsync_dir: "%s"\n' "${syncDir}" >> "$rimeInstallation"
      fi
    fi
  '';

  # rime 只在手动点「同步用户数据」时才同步，放着不管用户词典就没有备份也不会合并
  shelken.tasks.rime-sync = {
    when = "4:30";
    script = ''
      "${squirrel}" --sync
    '';
  };
}
