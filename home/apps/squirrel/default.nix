{lib, rime-main, rime-config, ...}:
let
  rimeDir = "Library/Rime";
  custom_file_list = builtins.attrNames
  (builtins.readDir (rime-config + "/custom")); 
  shit = builtins.listToAttrs (builtins.map (custom_file:
    {"Library/Rime-Test/${custom_file}".source = "${rime-config}/custom/${custom_file}";}
  ) custom_file_list);
  # 定義一個函數，它接受文件名和源文件的路徑，並返回相應的文件設置
  makeCustomFile = customFile: {
    "${rimeDir}/${customFile}.custom.yaml" = {
      source = "${rime-config}/custom/${customFile}.custom.yaml";
    };
  };
in 
{
  home.file = {
    "${rimeDir}" = {
      source = rime-main;
      recursive = true;
    };
    # (makeCustomFile "default");
    "${rimeDir}/default.custom.yaml" = {
      source = "${rime-config}/custom/default.custom.yaml";
    };
    "${rimeDir}/rime_ice.custom.yaml" = {
      source = "${rime-config}/custom/rime_ice.custom.yaml";
    };
    "${rimeDir}/squirrel.custom.yaml" = {
      source = "${rime-config}/custom/squirrel.custom.yaml";
    };
    "${rimeDir}/weasel.custom.yaml" = {
      source = "${rime-config}/custom/weasel.custom.yaml";
    };
  };

}
