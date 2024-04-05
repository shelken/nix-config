{
  lib,
  rime-main,
  rime-config,
  ...
}: let
  rimeDir = "Library/Rime";
  custom_file_list = builtins.attrNames (builtins.readDir (rime-config + "/custom"));
  custom_attrs = lib.attrsets.mergeAttrsList (builtins.map (
      custom_file: {"${rimeDir}/${custom_file}" = {source = "${rime-config}/custom/${custom_file}";};}
    )
    custom_file_list);
in {
  home.file =
    {
      "${rimeDir}" = {
        source = rime-main;
        recursive = true;
      };
    }
    // custom_attrs;
}
